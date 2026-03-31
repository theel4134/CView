// MARK: - CViewNetworking/ImageCacheService.swift
// 이미지 디스크 + 메모리 캐싱 서비스

import Foundation
import AppKit   // NSImage
import CryptoKit
import CViewCore

/// 이미지 캐싱 서비스 (actor 기반)
/// 메모리 캐시 (NSCache) + 디스크 캐시 (FileManager) 2단 구조
/// + 디코딩된 NSImage NSCache (렌더 패스에서 Data→NSImage 변환 제거)
public actor ImageCacheService {
    public static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, CacheEntry>()
    /// 3단: 디코딩 완료된 NSImage NSCache — body 평가 시 재디코딩 방지
    private let decodedImageCache = NSCache<NSString, NSImageWrapper>()
    private let diskCacheURL: URL
    private let maxDiskCacheSize: Int = ImageCacheDefaults.diskCacheMaxSize
    private let maxDiskCacheAge: TimeInterval = ImageCacheDefaults.diskCacheMaxAge

    /// 진행 중인 다운로드 태스크 — 동일 URL 중복 요청 방지 (thundering herd)
    private var inFlightDownloads: [String: Task<Data?, Never>] = [:]

    /// 주기적 디스크 캐시 정리 타이머 — 장시간 재생 시 만료 파일 자동 제거
    private var pruneTask: Task<Void, Never>?
    /// 캐시 정리 주기 (초) — 30분마다 만료 엔트리 삭제
    private let pruneInterval: TimeInterval = 1800

    /// 이미지 전용 URLSession — API 세션과 연결 풀 분리하여 경합 방지
    /// HTTP/2 멀티플렉싱 활성화, 쿠키 비활성화(이미지에 불필요)
    private static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = ImageCacheDefaults.requestTimeout
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // 자체 캐시 사용
        config.urlCache = nil                                       // URLCache 비활성화
        config.httpCookieAcceptPolicy = .never                      // 이미지에 쿠키 불필요
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    /// NSCache에 저장할 래퍼 (Sendable-safe)
    final class CacheEntry: @unchecked Sendable {
        let data: Data
        let timestamp: Date
        init(data: Data) {
            self.data = data
            self.timestamp = Date()
        }
    }

    /// 디코딩된 NSImage 래퍼
    final class NSImageWrapper: @unchecked Sendable {
        let image: NSImage
        init(_ image: NSImage) { self.image = image }
    }

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskCacheURL = cacheDir.appending(path: "com.cview.images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = ImageCacheDefaults.memoryCacheCountLimit
        memoryCache.totalCostLimit = ImageCacheDefaults.memoryCacheSizeLimit

        // 디코딩된 NSImage 캐시 — 렌더 패스에서 변환 비용 제거
        decodedImageCache.countLimit = ImageCacheDefaults.decodedCacheCountLimit
        decodedImageCache.totalCostLimit = ImageCacheDefaults.decodedCacheSizeLimit
        
        // 자동 캐시 정리 타이머 시작 — 장시간 재생 시 디스크 캐시 무한 증가 방지
        // init()은 nonisolated이므로 Task로 감싸서 actor context에서 실행
        Task { [weak self] in
            await self?.startAutoPruneTimer()
        }
    }
    
    // MARK: - Auto Prune Timer
    
    /// 주기적으로 만료된 디스크 캐시 엔트리를 정리
    private func startAutoPruneTimer() {
        pruneTask?.cancel()
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.pruneInterval ?? 1800) * 1_000_000_000))
                guard let self, !Task.isCancelled else { break }
                await self.pruneExpiredEntries()
            }
        }
    }

    // MARK: - Public API

    /// URL에서 이미지 데이터 가져오기 (캐시 우선)
    public func imageData(for url: URL) async -> Data? {
        let key = cacheKey(for: url)

        // 1. 메모리 캐시 확인
        if let entry = memoryCache.object(forKey: key as NSString) {
            return entry.data
        }

        // 2. 디스크 캐시 확인
        if let diskData = loadFromDisk(key: key) {
            let entry = CacheEntry(data: diskData)
            memoryCache.setObject(entry, forKey: key as NSString, cost: diskData.count)
            return diskData
        }

        // 3. 네트워크 다운로드
        return await downloadAndCache(url: url, key: key)
    }

    /// 디코딩된 NSImage 반환 — body 평가에서 Data→NSImage 변환 비용 제거
    /// 이미지 디코딩은 백그라운드 Task에서 수행되며 결과를 NSCache에 보관
    public func nsImage(for url: URL) async -> NSImage? {
        let key = cacheKey(for: url)
        let cacheKey = key as NSString

        // 1. 디코딩 캐시 확인 (가장 빠름)
        if let wrapper = decodedImageCache.object(forKey: cacheKey) {
            return wrapper.image
        }

        // 2. Data 캐시에서 꺼내 백그라운드 디코딩
        let data: Data?
        if let entry = memoryCache.object(forKey: cacheKey) {
            data = entry.data
        } else if let diskData = loadFromDisk(key: key) {
            let entry = CacheEntry(data: diskData)
            memoryCache.setObject(entry, forKey: cacheKey, cost: diskData.count)
            data = diskData
        } else {
            data = await downloadAndCache(url: url, key: key)
        }

        guard let data else { return nil }

        // 3. 백그라운드에서 디코딩 후 캐시 저장
        // .utility 우선순위: 렌더 파이프라인(.userInitiated)과 경합 방지
        // 진입 시 N개 카드 동시 디코딩이 렌더 패스와 충돌하던 문제 해결
        let image = await Task.detached(priority: .utility) {
            NSImage(data: data)
        }.value

        if let image {
            // 디코딩 비용 근사: 픽셀 크기 × 4 바이트
            let pixelSize = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? data.count
            decodedImageCache.setObject(NSImageWrapper(image), forKey: cacheKey, cost: pixelSize)
        }
        return image
    }

    /// nsImage(for:) — maxAge 버전 (라이브 썸네일용)
    public func nsImage(for url: URL, maxAge: TimeInterval) async -> NSImage? {
        let key = cacheKey(for: url)
        let cacheKey = key as NSString

        // 디코딩 캐시는 maxAge와 무관하게 우선 확인, 단 Data 캐시가 만료면 무효화
        if let entry = memoryCache.object(forKey: cacheKey) {
            if Date().timeIntervalSince(entry.timestamp) < maxAge {
                if let wrapper = decodedImageCache.object(forKey: cacheKey) {
                    return wrapper.image
                }
            } else {
                memoryCache.removeObject(forKey: cacheKey)
                decodedImageCache.removeObject(forKey: cacheKey)
            }
        }

        let data = await imageData(for: url, maxAge: maxAge)
        guard let data else { return nil }

        let image = await Task.detached(priority: .utility) {
            NSImage(data: data)
        }.value

        if let image {
            let pixelSize = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? data.count
            decodedImageCache.setObject(NSImageWrapper(image), forKey: cacheKey, cost: pixelSize)
        }
        return image
    }

    /// URL에서 이미지 데이터 가져오기 — 최대 캐시 유지 시간 지정 (라이브 썸네일용)
    /// - Parameter maxAge: 캐시 최대 유지 시간(초). 초과 시 새로 다운로드.
    public func imageData(for url: URL, maxAge: TimeInterval) async -> Data? {
        let key = cacheKey(for: url)

        // 1. 메모리 캐시 확인 (생성 시간 체크)
        if let entry = memoryCache.object(forKey: key as NSString) {
            if Date().timeIntervalSince(entry.timestamp) < maxAge {
                return entry.data
            }
            memoryCache.removeObject(forKey: key as NSString)
        }

        // 2. 디스크 캐시 확인 (maxAge 기반)
        if let diskData = loadFromDisk(key: key, maxAge: maxAge) {
            let entry = CacheEntry(data: diskData)
            memoryCache.setObject(entry, forKey: key as NSString, cost: diskData.count)
            return diskData
        }

        // 3. 네트워크 다운로드
        return await downloadAndCache(url: url, key: key)
    }

    /// 이미지 데이터 직접 캐시 저장 (metrics 서버 등 외부 소스용)
    public func store(data: Data, for url: URL) {
        let key = cacheKey(for: url)
        let entry = CacheEntry(data: data)
        memoryCache.setObject(entry, forKey: key as NSString, cost: data.count)
        let diskURL = diskPath(for: key)
        Task.detached(priority: .background) { [data] in
            try? data.write(to: diskURL, options: .atomic)
        }
    }

    // MARK: - Prefetch

    /// 여러 URL의 이미지를 백그라운드에서 미리 다운로드하여 캐시에 저장
    /// 이미 캐시에 있는 항목은 건너뜀. 최대 동시 다운로드 수 제한.
    /// - Parameters:
    ///   - urls: 프리페치할 이미지 URL 배열
    ///   - concurrency: 동시 다운로드 수 (기본 6)
    public func prefetch(_ urls: [URL], concurrency: Int = 6) async {
        // 캐시에 없는 URL만 필터링
        let uncached = urls.filter { url in
            let key = cacheKey(for: url) as NSString
            if memoryCache.object(forKey: key) != nil { return false }
            let diskURL = diskPath(for: String(key))
            return !FileManager.default.fileExists(atPath: diskURL.path)
        }
        guard !uncached.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var launched = 0
            for url in uncached {
                if launched >= concurrency {
                    await group.next()
                }
                launched += 1
                group.addTask { [weak self] in
                    _ = await self?.imageData(for: url)
                }
            }
        }
    }

    /// 프리페치 + 프리디코딩 — 다운로드와 NSImage 디코딩까지 완료하여 캐시에 저장
    /// 페이지 전환 시 다음 페이지 썸네일을 미리 디코딩하여 즉시 표시 가능
    /// - Parameters:
    ///   - urls: 프리페치할 이미지 URL 배열
    ///   - concurrency: 동시 처리 수 (기본 4)
    public func prefetchAndDecode(_ urls: [URL], concurrency: Int = 4) async {
        // 이미 디코딩 캐시에 있는 항목은 건너뜀
        let uncached = urls.filter { url in
            let key = cacheKey(for: url) as NSString
            return decodedImageCache.object(forKey: key) == nil
        }
        guard !uncached.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var launched = 0
            for url in uncached {
                if launched >= concurrency {
                    await group.next()
                }
                launched += 1
                group.addTask { [weak self] in
                    _ = await self?.nsImage(for: url)
                }
            }
        }
    }

    /// 캐시 전체 삭제
    public func clearAll() {
        memoryCache.removeAllObjects()
        decodedImageCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    /// 디스크 캐시만 삭제 (메모리 캐시 유지)
    public func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    /// 만료된 디스크 캐시 정리
    public func pruneExpiredEntries() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }

        let cutoff = Date().addingTimeInterval(-maxDiskCacheAge)
        var totalSize: Int = 0

        for fileURL in files {
            guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { continue }
            if let modDate = attrs.contentModificationDate, modDate < cutoff {
                try? fm.removeItem(at: fileURL)
            } else {
                totalSize += attrs.fileSize ?? 0
            }
        }

        // 최대 크기 초과 시 오래된 파일부터 삭제
        if totalSize > maxDiskCacheSize {
            let sorted = files.compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
                return (url, date)
            }.sorted { $0.1 < $1.1 }

            var freed = 0
            for (url, _) in sorted {
                guard totalSize - freed > maxDiskCacheSize else { break }
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    try? fm.removeItem(at: url)
                    freed += size
                }
            }
        }
    }

    // MARK: - Private

    private func cacheKey(for url: URL) -> String {
        let input = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: input)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func diskPath(for key: String) -> URL {
        diskCacheURL.appending(path: key)
    }

    private func loadFromDisk(key: String) -> Data? {
        let path = diskPath(for: key)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        // 만료 확인
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > maxDiskCacheAge {
            try? FileManager.default.removeItem(at: path)
            return nil
        }

        return try? Data(contentsOf: path)
    }

    private func loadFromDisk(key: String, maxAge: TimeInterval) -> Data? {
        let path = diskPath(for: key)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > maxAge {
            try? FileManager.default.removeItem(at: path)
            return nil
        }

        return try? Data(contentsOf: path)
    }

    private func saveToDisk(data: Data, key: String) {
        let path = diskPath(for: key)
        try? data.write(to: path, options: .atomic)
    }

    private func downloadAndCache(url: URL, key: String) async -> Data? {
        // 동일 URL이 이미 다운로드 중이면 해당 Task를 재사용 (네트워크 중복 요청 방지)
        if let existing = inFlightDownloads[key] {
            return await existing.value
        }

        let task = Task<Data?, Never> {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData  // 자체 캐시 사용
                request.timeoutInterval = ImageCacheDefaults.requestTimeout

                let (data, response) = try await ImageCacheService.imageSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      !data.isEmpty else { return nil }
                return data
            } catch {
                return nil
            }
        }

        inFlightDownloads[key] = task
        let data = await task.value
        inFlightDownloads.removeValue(forKey: key)

        if let data {
            let entry = CacheEntry(data: data)
            memoryCache.setObject(entry, forKey: key as NSString, cost: data.count)
            // 디스크 저장을 백그라운드로 분리 — actor 블로킹 방지
            let diskURL = diskPath(for: key)
            Task.detached(priority: .background) { [data] in
                try? data.write(to: diskURL, options: .atomic)
            }
        }

        return data
    }
}
