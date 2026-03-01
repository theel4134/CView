// MARK: - StreamRecordingService.swift
// CViewPlayer — HLS 스트림 세그먼트 기반 녹화 서비스
//
// 엔진 독립적인 녹화 구현: HLS playlist URL에서 세그먼트를 순차 다운로드하여
// MPEG-TS 파일로 연결 저장한다.
// VLC/AVPlayer 모두에서 폴백으로 사용 가능.

import Foundation
import CViewCore
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
        
        while !Task.isCancelled && state == .recording {
            do {
                let segmentURLs = try await fetchSegmentURLs(from: playlistURL)
                
                for segmentURL in segmentURLs {
                    guard !Task.isCancelled && state == .recording else { break }
                    
                    let uri = segmentURL.absoluteString
                    guard !downloadedSegmentURIs.contains(uri) else { continue }
                    
                    // 세그먼트 다운로드 및 기록
                    do {
                        let (data, _) = try await session.data(from: segmentURL)
                        try writeData(data)
                        downloadedSegmentURIs.insert(uri)
                    } catch {
                        if !Task.isCancelled {
                            logger.warning("세그먼트 다운로드 실패: \(error.localizedDescription, privacy: .public)")
                        }
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
    
    /// m3u8 playlist에서 세그먼트 URL 목록 추출
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
