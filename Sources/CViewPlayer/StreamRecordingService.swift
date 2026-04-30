// MARK: - StreamRecordingService.swift
// CViewPlayer — HLS 스트림 세그먼트 기반 녹화 서비스
//
// 엔진 독립적인 녹화 구현: HLS playlist URL에서 세그먼트를 순차 다운로드하여
// MPEG-TS 파일로 연결 저장한다.
// VLC/AVPlayer 모두에서 폴백으로 사용 가능.
//
// v2 개선사항 (flashls FragmentLoader/AES 참조):
// - AES-128-CBC 암호화 세그먼트 복호화 지원
// - 세그먼트 단위 지수 백오프 재시도 (flashls _fraghandleIOError)
// - PTS 정규화 유틸리티 연동

import Foundation
import CViewCore
import CryptoKit
import CommonCrypto
import os.log

// MARK: - Recording State

/// 녹화 상태
public enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case stopping
    case error(String)
}

// MARK: - Stream Recording Service

/// HLS 세그먼트 순차 다운로드 기반 스트림 녹화 서비스.
/// 라이브 스트림의 m3u8 playlist를 주기적으로 폴링하여
/// 새 세그먼트를 발견하면 다운로드 후 출력 파일에 append 한다.
public actor StreamRecordingService {
    
    // MARK: - Properties
    
    private let logger = AppLogger.player
    private var state: RecordingState = .idle
    private var outputFileHandle: FileHandle?
    private var outputURL: URL?
    private var recordingTask: Task<Void, Never>?
    private var downloadedSegmentURIs: Set<String> = []
    private var totalBytesWritten: Int64 = 0
    private var startDate: Date?
    
    deinit {
        recordingTask?.cancel()
        try? outputFileHandle?.close()
        session.invalidateAndCancel()
    }
    
    /// URLSession for downloading segments
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": CommonHeaders.safariUserAgent,
            "Referer": CommonHeaders.chzzkReferer
        ]
        return URLSession(configuration: config)
    }()
    
    // MARK: - Public Interface
    
    /// 현재 녹화 상태
    public var currentState: RecordingState { state }
    
    /// 녹화 시작 시각
    public var recordingStartDate: Date? { startDate }
    
    /// 녹화 중 여부
    public var isRecording: Bool { state == .recording }
    
    /// 기록된 총 바이트 수
    public var bytesWritten: Int64 { totalBytesWritten }
    
    /// 녹화 시작
    /// - Parameters:
    ///   - playlistURL: HLS master/media playlist URL (.m3u8)
    ///   - outputURL: 저장할 파일 경로 (.ts)
    public func startRecording(playlistURL: URL, to outputURL: URL) throws {
        guard state == .idle else {
            throw PlayerError.recordingFailed("이미 녹화 중입니다")
        }

        // 출력 디렉토리 생성
        let dir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // 출력 파일 생성
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: outputURL.path) else {
            throw PlayerError.recordingFailed("출력 파일을 생성할 수 없습니다: \(outputURL.path)")
        }
        
        self.outputFileHandle = handle
        self.outputURL = outputURL
        self.downloadedSegmentURIs = []
        self.totalBytesWritten = 0
        self.startDate = Date()
        self.state = .recording
        
        logger.info("녹화 시작: \(outputURL.lastPathComponent, privacy: .public)")
        
        // 세그먼트 폴링 시작
        recordingTask = Task { [weak self] in
            await self?.segmentPollingLoop(playlistURL: playlistURL)
        }
    }
    
    /// 녹화 중지
    public func stopRecording() {
        guard state == .recording else { return }
        
        state = .stopping
        recordingTask?.cancel()
        recordingTask = nil
        
        // 파일 핸들 닫기
        try? outputFileHandle?.close()
        outputFileHandle = nil
        
        let bytes = totalBytesWritten
        let segments = downloadedSegmentURIs.count
        logger.info("녹화 중지: \(segments)개 세그먼트, \(bytes) bytes 저장됨")
        
        state = .idle
    }
    
    // MARK: - Segment Polling
    
    /// m3u8 playlist를 주기적으로 폴링하여 새 세그먼트를 다운로드
    private func segmentPollingLoop(playlistURL: URL) async {
        let pollInterval: Duration = .seconds(2)
        let parser = HLSManifestParser()
        
        while !Task.isCancelled && state == .recording {
            do {
                let segments = try await fetchParsedSegments(from: playlistURL, parser: parser)
                
                for segment in segments {
                    guard !Task.isCancelled && state == .recording else { break }
                    
                    let uri = segment.uri.absoluteString
                    guard !downloadedSegmentURIs.contains(uri) else { continue }
                    
                    // flashls FragmentLoader 참조: 세그먼트 단위 지수 백오프 재시도
                    var data: Data?
                    var retryTimeout: TimeInterval = 1.0
                    let maxRetries = 3

                    for attempt in 0..<maxRetries {
                        do {
                            let (downloaded, _) = try await session.data(from: segment.uri)
                            data = downloaded
                            break
                        } catch {
                            if Task.isCancelled { break }
                            if attempt < maxRetries - 1 {
                                logger.warning("세그먼트 다운로드 실패 (시도 \(attempt + 1)/\(maxRetries)): \(error.localizedDescription, privacy: .public)")
                                // flashls: retryTimeout = min(64s, 2 × previous)
                                try? await Task.sleep(for: .seconds(retryTimeout))
                                retryTimeout = min(64.0, retryTimeout * 2.0)
                            } else {
                                logger.warning("세그먼트 다운로드 최종 실패: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }

                    guard var segmentData = data else { continue }

                    // AES-128-CBC 복호화 (flashls AES.as 참조)
                    if let encryption = segment.encryptionInfo {
                        do {
                            segmentData = try await decryptSegment(segmentData, encryption: encryption)
                        } catch {
                            logger.warning("세그먼트 복호화 실패: \(error.localizedDescription, privacy: .public)")
                            continue
                        }
                    }

                    do {
                        try writeData(segmentData)
                        downloadedSegmentURIs.insert(uri)
                    } catch {
                        logger.warning("세그먼트 쓰기 실패: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    logger.warning("Playlist 폴링 실패: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            try? await Task.sleep(for: pollInterval)
        }
    }

    // MARK: - Parsed Segment Fetching

    /// HLSManifestParser를 사용하여 세그먼트 정보 (암호화 포함) 추출
    private func fetchParsedSegments(
        from playlistURL: URL,
        parser: HLSManifestParser
    ) async throws -> [MediaPlaylist.Segment] {
        let (data, _) = try await session.data(from: playlistURL)
        guard let content = String(data: data, encoding: .utf8) else { return [] }

        // 마스터 플레이리스트 감지 → 첫 번째 variant의 미디어 플레이리스트로 재귀
        if content.contains("#EXT-X-STREAM-INF") {
            let master = try parser.parseMasterPlaylist(content: content, baseURL: playlistURL)
            // 비트레이트 내림차순 정렬 → 첫 번째(최고 화질) 사용
            if let firstVariant = master.variants.first {
                return try await fetchParsedSegments(from: firstVariant.uri, parser: parser)
            }
            return []
        }

        let media = try parser.parseMediaPlaylist(content: content, baseURL: playlistURL)
        return media.segments
    }

    // MARK: - AES-128-CBC Decryption (flashls AES.as 참조)

    /// AES-128-CBC 세그먼트 복호화 — CryptoKit 하드웨어 가속 사용
    /// flashls의 CBC 복호화 + PKCS7 unpadding을 Swift native로 구현
    private func decryptSegment(_ data: Data, encryption: MediaPlaylist.EncryptionInfo) async throws -> Data {
        guard encryption.method == .aes128 else {
            throw PlayerError.recordingFailed("지원하지 않는 암호화 방식: \(encryption.method.rawValue)")
        }

        // 키 다운로드 (캐시)
        let keyData = try await fetchEncryptionKey(url: encryption.uri)
        guard keyData.count == 16 else {
            throw PlayerError.recordingFailed("잘못된 AES 키 크기: \(keyData.count) bytes")
        }

        guard let iv = encryption.iv, iv.count == 16 else {
            throw PlayerError.recordingFailed("IV가 없거나 크기가 잘못됨")
        }

        // AES-128-CBC 복호화 — CommonCrypto 사용 (CryptoKit의 AES.GCM이 아닌 CBC 모드)
        let decrypted = try aes128CBCDecrypt(data: data, key: keyData, iv: iv)
        return decrypted
    }

    /// AES 키 캐시 — 동일 URL의 키를 반복 다운로드하지 않음
    private var keyCache: [URL: Data] = [:]

    private func fetchEncryptionKey(url: URL) async throws -> Data {
        if let cached = keyCache[url] { return cached }
        let (data, _) = try await session.data(from: url)
        keyCache[url] = data
        return data
    }

    /// AES-128-CBC 복호화 + PKCS7 unpadding (flashls AES._decryptCBC + unpad)
    private func aes128CBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        // CommonCrypto를 사용한 CBC 복호화
        let bufferSize = data.count + kCCBlockSizeAES128
        var outData = Data(count: bufferSize)
        var outLength = 0

        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            inBytes.baseAddress, data.count,
                            outBytes.baseAddress, bufferSize,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw PlayerError.recordingFailed("AES 복호화 실패 (CCCrypt status: \(status))")
        }

        return outData.prefix(outLength)
    }
    
    /// m3u8 playlist에서 세그먼트 URL 목록 추출 (레거시 호환용)
    private func fetchSegmentURLs(from playlistURL: URL) async throws -> [URL] {
        let (data, _) = try await session.data(from: playlistURL)
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        
        let lines = content.components(separatedBy: .newlines)
        var segmentURLs: [URL] = []
        
        // 미디어 playlist인지 확인 (세그먼트가 있는 경우)
        let isMediaPlaylist = lines.contains(where: { $0.hasPrefix("#EXTINF:") })
        
        if isMediaPlaylist {
            // 미디어 playlist — 세그먼트 URL 추출
            var nextIsSegment = false
            for line in lines {
                if line.hasPrefix("#EXTINF:") {
                    nextIsSegment = true
                    continue
                }
                if nextIsSegment && !line.isEmpty && !line.hasPrefix("#") {
                    if let url = resolveURL(line, relativeTo: playlistURL) {
                        segmentURLs.append(url)
                    }
                    nextIsSegment = false
                }
            }
        } else {
            // 마스터 playlist — 첫 번째 variant의 미디어 playlist URL 찾기
            for line in lines {
                if !line.hasPrefix("#") && !line.isEmpty && line.contains(".m3u8") {
                    if let mediaURL = resolveURL(line, relativeTo: playlistURL) {
                        // 재귀적으로 미디어 playlist 파싱
                        return try await fetchSegmentURLs(from: mediaURL)
                    }
                }
            }
        }
        
        return segmentURLs
    }
    
    /// 상대 URL을 절대 URL로 변환
    private func resolveURL(_ path: String, relativeTo base: URL) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return URL(string: path, relativeTo: base)
    }
    
    /// 데이터를 출력 파일에 기록
    private func writeData(_ data: Data) throws {
        guard let handle = outputFileHandle else {
            throw PlayerError.recordingFailed("출력 파일 핸들이 없습니다")
        }
        handle.seekToEndOfFile()
        handle.write(data)
        totalBytesWritten += Int64(data.count)
    }
    
    // MARK: - Helpers
    
    /// 기본 녹화 저장 경로 생성
    /// ~/Movies/CView/channelName_timestamp.ts
    public static func defaultRecordingURL(channelName: String) -> URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cviewDir = moviesDir.appendingPathComponent("CView")
        
        let sanitized = channelName.replacingOccurrences(
            of: "[^a-zA-Z0-9가-힣ㄱ-ㅎㅏ-ㅣ_-]",
            with: "_",
            options: .regularExpression
        )
        let timestamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
        ).replacingOccurrences(of: ":", with: "-")
        
        let filename = "\(sanitized)_\(timestamp).ts"
        return cviewDir.appendingPathComponent(filename)
    }
}
