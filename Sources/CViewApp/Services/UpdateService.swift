// MARK: - UpdateService.swift
// CViewApp - 자동 업데이트 서비스
//
// GitHub Releases API 를 폴링하여 최신 릴리스를 감지하고,
// .zip/.dmg asset 을 다운로드한 뒤 현재 앱 번들을 교체하고 재실행.
//
// [2026-04-19] ad-hoc 서명 앱이므로 Sparkle EdDSA 흐름 대신 수동 교체 방식을 사용.
//   - 다운로드 → 검증 → 쉘 스크립트로 백그라운드 교체 → 재실행 → 현재 프로세스 종료.

import Foundation
import AppKit
import Combine
import CViewCore

// MARK: - Update Status

enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(GitHubRelease)
    case downloading(progress: Double)
    case readyToInstall(URL)      // 로컬 .app 경로 (교체 대상)
    case installing
    case error(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

// MARK: - GitHub Release Model

struct GitHubRelease: Codable, Equatable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL?
    let publishedAt: Date?
    let assets: [Asset]

    struct Asset: Codable, Equatable, Sendable {
        let name: String
        let size: Int
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// `v2.0.1` → `"2.0.1"` (접두어 제거)
    var versionString: String {
        if tagName.hasPrefix("v") || tagName.hasPrefix("V") {
            return String(tagName.dropFirst())
        }
        return tagName
    }

    /// .zip asset 우선, 없으면 .dmg
    var preferredAsset: Asset? {
        assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
            ?? assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
    }

    /// asset 이름(`CView-2.0.0-65.zip`)에서 빌드 번호를 추출.
    /// release_to_github.sh 가 `${APP_NAME}-${VERSION}-${BUILD_NUMBER}.zip` 으로 명명하므로,
    /// 동일 버전 안에서도 빌드 단위 업데이트 감지가 가능하다.
    var buildNumber: Int? {
        guard let asset = preferredAsset else { return nil }
        // 예: "CView-2.0.0-65.zip" → "65"
        let stem = (asset.name as NSString).deletingPathExtension
        guard let dashIndex = stem.lastIndex(of: "-") else { return nil }
        let tail = stem[stem.index(after: dashIndex)...]
        return Int(tail)
    }
}

// MARK: - Update Service

@Observable
@MainActor
final class UpdateService {

    // MARK: - Configuration

    /// GitHub 저장소 (owner/repo)
    static let repository = "theel4134/CView"

    private var latestReleaseURL: URL {
        // 캐시버스터: URLSession.shared 가 완전히 캐시를 우회하지 못하는 경우를 대비해
        // 요청 URL 에 매번 달라지는 타임스탬프를 첨부.
        let ts = Int(Date().timeIntervalSince1970)
        return URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest?_ts=\(ts)")!
    }

    // MARK: - State (Observable)

    var status: UpdateStatus = .idle
    var latestRelease: GitHubRelease?

    /// 마지막으로 확인한 시각
    var lastCheckedAt: Date?

    // MARK: - Private

    private let logger = AppLogger.app
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Public API

    /// 현재 앱 버전 (`CFBundleShortVersionString`, 예: "2.0.0")
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 현재 앱 빌드 번호 (`CFBundleVersion`, 예: "65")
    var currentBuild: Int {
        guard let s = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              let n = Int(s) else { return 0 }
        return n
    }

    /// 업데이트 확인
    func checkForUpdates(silent: Bool = false) async {
        if status.isBusy { return }
        if !silent { status = .checking }

        do {
            var request = URLRequest(url: latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("CView/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            // [Fix] URLSession.shared 기본 디스크 캐시 우회 — GitHub 가 붙이는
            // Cache-Control: public, max-age=60 때문에 방금 게시된 릴리스가 잠시 동안 보이지 않는 문제를 방지.
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            guard http.statusCode == 200 else {
                // 404 = 릴리스 없음 → 최신으로 간주
                if http.statusCode == 404 {
                    lastCheckedAt = Date()
                    status = .upToDate
                    return
                }
                throw UpdateError.httpStatus(http.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(GitHubRelease.self, from: data)

            lastCheckedAt = Date()
            latestRelease = release

            // 버전(semver) + 빌드 번호를 함께 비교하여 동일 버전 내 빌드 업데이트도 감지.
            let verCmp = Self.compareVersions(release.versionString, currentVersion)
            let latestBuild = release.buildNumber
            let isNewer: Bool = {
                switch verCmp {
                case .orderedDescending: return true
                case .orderedAscending:  return false
                case .orderedSame:
                    // 버전 동일 → 빌드 번호로 비교. asset 명에 번호가 없으면 최신으로 간주.
                    if let lb = latestBuild { return lb > self.currentBuild }
                    return false
                }
            }()

            if isNewer {
                status = .updateAvailable(release)
                let latestLabel = latestBuild.map { "\(release.versionString) (build \($0))" } ?? release.versionString
                logger.info("Update available: \(latestLabel) (current: \(self.currentVersion) build \(self.currentBuild))")
            } else {
                status = .upToDate
                logger.info("App is up to date (\(self.currentVersion) build \(self.currentBuild))")
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            if !silent {
                status = .error("업데이트 확인 실패: \(error.localizedDescription)")
            } else {
                status = .idle
            }
        }
    }

    /// 다운로드 + 설치 시작
    func downloadAndInstall() async {
        guard case .updateAvailable(let release) = status else { return }
        guard let asset = release.preferredAsset else {
            status = .error("다운로드 가능한 업데이트 파일(.zip/.dmg)이 없습니다.")
            return
        }

        // 1) 현재 앱이 읽기 전용 위치(DMG 마운트 등)에서 실행 중이면 거부
        let currentAppURL = Bundle.main.bundleURL
        if !FileManager.default.isWritableFile(atPath: currentAppURL.deletingLastPathComponent().path) {
            status = .error("현재 앱 위치(\(currentAppURL.deletingLastPathComponent().path))에 쓰기 권한이 없습니다. .app 을 /Applications 또는 쓰기 가능한 폴더로 옮겨주세요.")
            return
        }

        status = .downloading(progress: 0)

        do {
            // 2) 다운로드
            let downloadedFile = try await downloadAsset(asset)

            // 3) 추출 → 새 .app 경로 확보
            let newAppURL = try await extractApp(from: downloadedFile, assetName: asset.name)

            // 4) xattr 일괄 제거 (quarantine + provenance 등) + ad-hoc 재서명
            // macOS 15+ Gatekeeper 는 com.apple.quarantine 가 없어도 com.apple.provenance 나
            // 기타 ls-attrs 를 이유로 차단할 수 있으므로 -cr 로 전체 제거.
            _ = try? await runProcess("/usr/bin/xattr", args: ["-cr", newAppURL.path])
            _ = try? await runProcess("/usr/bin/codesign", args: ["--force", "--deep", "--sign", "-", newAppURL.path])

            status = .readyToInstall(newAppURL)

            // 5) 설치 스크립트 실행 후 현재 앱 종료
            try installAndRelaunch(newAppURL: newAppURL, targetURL: currentAppURL)
        } catch {
            logger.error("Update install failed: \(error.localizedDescription)")
            status = .error("업데이트 실패: \(error.localizedDescription)")
        }
    }

    /// 사용자가 명시적으로 닫을 때 호출 (idle 로 복귀)
    func dismissError() {
        if case .error = status {
            status = .idle
        }
    }

    // MARK: - Download

    private func downloadAsset(_ asset: GitHubRelease.Asset) async throws -> URL {
        let cachesDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let updatesDir = cachesDir.appendingPathComponent("CViewUpdates", isDirectory: true)
        try? FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
        let destination = updatesDir.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: destination)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: asset.browserDownloadURL) { [weak self] tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: UpdateError.invalidResponse)
                    return
                }
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
                Task { @MainActor in self?.progressObservation = nil }
            }

            self.progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let p = progress.fractionCompleted
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.status {
                        self.status = .downloading(progress: p)
                    }
                }
            }
            self.downloadTask = task
            task.resume()
        }
    }

    // MARK: - Extract

    private func extractApp(from archive: URL, assetName: String) async throws -> URL {
        let cachesDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let extractDir = cachesDir.appendingPathComponent("CViewUpdates/extracted-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let lower = assetName.lowercased()
        if lower.hasSuffix(".zip") {
            // ditto 가 resource fork/확장 속성 보존에 더 안전
            _ = try await runProcess("/usr/bin/ditto", args: ["-xk", archive.path, extractDir.path])
        } else if lower.hasSuffix(".dmg") {
            // DMG 마운트 → .app 복사 → detach
            let mountOut = try await runProcess("/usr/bin/hdiutil", args: ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", archive.path])
            // 출력 마지막 라인의 마운트 경로 파싱 ("/dev/diskXsY\t...\t/Volumes/NAME")
            let mountPoint = mountOut
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let parts = line.split(separator: "\t").map(String.init)
                    return parts.last.flatMap { $0.hasPrefix("/Volumes/") ? $0.trimmingCharacters(in: .whitespaces) : nil }
                }
                .last
            guard let mountPath = mountPoint else {
                throw UpdateError.dmgMountFailed
            }
            defer {
                Task.detached {
                    _ = try? await Self.runProcessStatic("/usr/bin/hdiutil", args: ["detach", mountPath, "-force"])
                }
            }
            // .app 파일 찾기
            let contents = try FileManager.default.contentsOfDirectory(atPath: mountPath)
            guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                throw UpdateError.appNotFoundInArchive
            }
            let sourceAppPath = (mountPath as NSString).appendingPathComponent(appName)
            let destAppPath = extractDir.appendingPathComponent(appName).path
            _ = try await runProcess("/bin/cp", args: ["-R", sourceAppPath, destAppPath])
        } else {
            throw UpdateError.unsupportedArchive(assetName)
        }

        // extractDir 내에서 .app 검색 (최상위 또는 중첩)
        if let found = Self.findAppBundle(in: extractDir) {
            return found
        }
        throw UpdateError.appNotFoundInArchive
    }

    private static func findAppBundle(in dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }

    // MARK: - Install + Relaunch

    /// `/tmp` 에 설치 스크립트를 만들고 백그라운드에서 실행 → 현재 앱 종료.
    /// 스크립트는 현재 PID 가 종료될 때까지 대기 후, 번들을 교체하고 `open` 으로 재실행.
    private func installAndRelaunch(newAppURL: URL, targetURL: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = URL(fileURLWithPath: "/tmp/cview_update_\(UUID().uuidString.prefix(8)).sh")

        let script = """
        #!/bin/zsh
        set -e

        # 1) 현재 앱 프로세스 종료 대기 (최대 30s)
        for i in {1..150}; do
            if ! kill -0 \(pid) 2>/dev/null; then
                break
            fi
            sleep 0.2
        done

        # 2) 번들 교체
        TARGET=\(shellQuote(targetURL.path))
        NEW=\(shellQuote(newAppURL.path))

        # 기존 번들 백업 (롤백 안전장치)
        BACKUP="${TARGET}.backup-$(date +%s)"
        if [ -d "$TARGET" ]; then
            mv "$TARGET" "$BACKUP" || exit 1
        fi

        # 새 번들 이동 (복사보다 빠르고 원자적)
        if ! mv "$NEW" "$TARGET"; then
            # 실패 시 백업 복원
            [ -d "$BACKUP" ] && mv "$BACKUP" "$TARGET"
            exit 1
        fi

        # 성공 시 백업 삭제 (비차단 — 실패해도 무방)
        rm -rf "$BACKUP" &

        # 3) xattr 일괄 제거 (Gatekeeper 차단 방지 — macOS 15+ 의 com.apple.provenance 포함)
        xattr -cr "$TARGET" 2>/dev/null || true

        # 4) LaunchServices 재등록 (Info.plist 변경 반영)
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$TARGET" 2>/dev/null || true

        # 5) 새 버전 실행
        open "$TARGET"

        # 6) 스크립트 자체 삭제 (비차단)
        rm -f \(shellQuote(scriptURL.path)) &
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // 디태치드 실행 (부모가 종료돼도 계속 동작)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil
        try process.run()

        status = .installing
        logger.info("Update installer launched (pid=\(pid), script=\(scriptURL.path))")

        // 현재 앱 종료 — 0.5s 후 terminate 호출 (스크립트가 kill -0 대기를 시작할 시간 확보)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func runProcess(_ executable: String, args: [String]) async throws -> String {
        try await Self.runProcessStatic(executable, args: args)
    }

    private static func runProcessStatic(_ executable: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = ((try? pipe.fileHandleForReading.readToEnd()) ?? nil) ?? Data()
                let output = String(data: data, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UpdateError.processFailed(executable, proc.terminationStatus, output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 세 자리 semver 비교 ("2.0.1" vs "2.0.0").
    /// 비정상 포맷은 문자열 비교로 fallback.
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - Error

enum UpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unsupportedArchive(String)
    case appNotFoundInArchive
    case dmgMountFailed
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "서버 응답이 올바르지 않습니다."
        case .httpStatus(let code): return "HTTP \(code) 오류"
        case .unsupportedArchive(let name): return "지원하지 않는 파일 형식: \(name)"
        case .appNotFoundInArchive: return "다운로드한 파일에서 .app 번들을 찾을 수 없습니다."
        case .dmgMountFailed: return "DMG 마운트 실패"
        case .processFailed(let exec, let code, let out):
            return "\(exec) 실행 실패 (\(code)): \(out.prefix(200))"
        }
    }
}
