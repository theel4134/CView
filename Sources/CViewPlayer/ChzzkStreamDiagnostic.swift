// MARK: - ChzzkStreamDiagnostic.swift
// CViewPlayer - Chzzk CDN 스트림 진단 도구
//
// VLC 프록시 바이패스 실험의 전제조건 검증을 위한 진단 유틸리티.
// Chzzk CDN의 M3U8 구조(EXT-X-MAP 유무), 세그먼트 Content-Type,
// 실제 데이터 포맷(fMP4/TS)을 분석합니다.
//
// 참조: VLC_DIRECT_PLAYBACK_RESEARCH.md §8 (실험적 검증 절차)

import Foundation
import CViewCore

// MARK: - Diagnostic Models

/// M3U8 분석 결과
public struct M3U8Analysis: Sendable {
    /// EXT-X-MAP 태그 존재 여부 (fMP4 init 세그먼트 참조)
    public let hasExtXMap: Bool
    /// EXT-X-MAP URI 값 (있는 경우)
    public let extXMapURI: String?
    /// HLS 버전 (#EXT-X-VERSION)
    public let version: Int
    /// 세그먼트 URL의 파일 확장자 목록
    public let segmentExtensions: [String]
    /// 첫 5개 세그먼트 URL
    public let sampleSegmentURLs: [URL]
    /// M3U8 원본 내용
    public let rawContent: String
    /// 이 M3U8가 마스터 플레이리스트인지
    public let isMasterPlaylist: Bool

    /// 진단 요약 문자열
    public var summary: String {
        var lines: [String] = []
        lines.append("=== M3U8 Analysis ===")
        lines.append("Type: \(isMasterPlaylist ? "Master" : "Media") Playlist")
        lines.append("HLS Version: \(version)")
        lines.append("EXT-X-MAP: \(hasExtXMap ? "✅ YES (\(extXMapURI ?? "?"))" : "❌ NO")")
        lines.append("Segment Extensions: \(segmentExtensions.isEmpty ? "(none)" : segmentExtensions.joined(separator: ", "))")
        lines.append("Sample Segments: \(sampleSegmentURLs.count)")
        return lines.joined(separator: "\n")
    }
}

/// 세그먼트 분석 결과
public struct SegmentAnalysis: Sendable {
    /// CDN 응답의 Content-Type 헤더 값
    public let contentType: String
    /// HTTP 상태 코드
    public let httpStatusCode: Int
    /// Magic bytes 기반 실제 포맷 식별
    public let actualFormat: SegmentFormat
    /// 첫 16바이트 (hex dump용)
    public let magicBytes: [UInt8]
    /// Content-Type과 실제 포맷의 불일치 여부
    public let contentTypeMismatch: Bool
    /// 세그먼트 크기 (bytes)
    public let dataSize: Int
    /// ISO BMFF 박스 타입 (fMP4인 경우)
    public let isobmffBoxType: String?

    /// 진단 요약 문자열
    public var summary: String {
        var lines: [String] = []
        lines.append("=== Segment Analysis ===")
        lines.append("HTTP Status: \(httpStatusCode)")
        lines.append("Content-Type: \(contentType)")
        lines.append("Actual Format: \(actualFormat.description)")
        if let box = isobmffBoxType {
            lines.append("ISO BMFF Box: \(box)")
        }
        lines.append("Size: \(dataSize) bytes")
        lines.append("Magic Bytes: \(magicBytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))")
        lines.append("Content-Type Mismatch: \(contentTypeMismatch ? "⚠️ YES" : "✅ NO")")
        return lines.joined(separator: "\n")
    }
}

/// 세그먼트 실제 포맷
public enum SegmentFormat: Sendable, CustomStringConvertible {
    case fMP4(boxType: String)  // ISO BMFF fMP4 (ftyp, styp, moof, moov)
    case mpegTS                 // MPEG-2 Transport Stream (0x47 sync)
    case unknown(String)        // 알 수 없는 포맷
    case insufficientData       // 데이터 부족 (< 8 bytes)

    public var description: String {
        switch self {
        case .fMP4(let box): return "fMP4 (ISO BMFF, box=\(box))"
        case .mpegTS: return "MPEG-2 TS"
        case .unknown(let info): return "Unknown (\(info))"
        case .insufficientData: return "Insufficient data"
        }
    }

    /// VLC probing이 이 포맷을 정확히 감지할 수 있는지
    public var vlcProbingWouldDetect: Bool {
        switch self {
        case .fMP4: return true    // styp/moof/ftyp/moov → MP4 감지
        case .mpegTS: return true  // 0x47 → TS 감지
        case .unknown, .insufficientData: return false
        }
    }
}

/// 종합 진단 결과
public struct StreamDiagnosticResult: Sendable {
    public let m3u8: M3U8Analysis
    public let segments: [SegmentAnalysis]
    public let initSegment: SegmentAnalysis?
    public let proxyBypassFeasibility: ProxyBypassFeasibility
    public let timestamp: Date

    /// 진단 요약 문자열
    public var summary: String {
        var lines: [String] = []
        lines.append("╔══════════════════════════════════════════╗")
        lines.append("║  Chzzk Stream Diagnostic Report          ║")
        lines.append("║  \(ISO8601DateFormatter().string(from: timestamp))  ║")
        lines.append("╚══════════════════════════════════════════╝")
        lines.append("")
        lines.append(m3u8.summary)
        lines.append("")
        if let initSeg = initSegment {
            lines.append("=== Init Segment ===")
            lines.append(initSeg.summary)
            lines.append("")
        }
        for (i, seg) in segments.enumerated() {
            lines.append("=== Media Segment #\(i + 1) ===")
            lines.append(seg.summary)
            lines.append("")
        }
        lines.append("=== Proxy Bypass Feasibility ===")
        lines.append(proxyBypassFeasibility.summary)
        return lines.joined(separator: "\n")
    }
}

/// 프록시 바이패스 가능성 판정
public struct ProxyBypassFeasibility: Sendable {
    public let feasible: Bool
    public let confidence: Confidence
    public let reasons: [String]
    public let risks: [String]

    public enum Confidence: String, Sendable {
        case high = "HIGH"
        case medium = "MEDIUM"
        case low = "LOW"
        case notFeasible = "NOT_FEASIBLE"
    }

    public var summary: String {
        var lines: [String] = []
        lines.append("Feasible: \(feasible ? "✅ YES" : "❌ NO")")
        lines.append("Confidence: \(confidence.rawValue)")
        if !reasons.isEmpty {
            lines.append("Reasons:")
            for r in reasons { lines.append("  - \(r)") }
        }
        if !risks.isEmpty {
            lines.append("Risks:")
            for r in risks { lines.append("  ⚠️ \(r)") }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Diagnostic Actor

/// Chzzk CDN에 대한 비파괴 진단을 수행하는 액터.
/// CDN 응답 분석만 수행하며 앱 재생 상태에 영향을 주지 않음.
///
/// 사용 예:
/// ```swift
/// let diagnostic = ChzzkStreamDiagnostic()
/// let result = try await diagnostic.runFullDiagnostic(masterURL: url)
/// print(result.summary)
/// ```
public actor ChzzkStreamDiagnostic {

    private let logger = AppLogger.player
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Full Diagnostic

    /// 종합 진단 실행: M3U8 → 세그먼트 → 판정
    /// - Parameter masterURL: HLS 마스터 매니페스트 URL
    /// - Returns: 종합 진단 결과
    public func runFullDiagnostic(masterURL: URL) async throws -> StreamDiagnosticResult {
        logger.info("[Diagnostic] Starting full diagnostic for: \(masterURL.host ?? "unknown")")

        // 1단계: 마스터 매니페스트 분석
        let masterAnalysis = try await analyzeM3U8(url: masterURL)

        // 마스터 플레이리스트면 첫 variant의 미디어 플레이리스트 분석
        let mediaAnalysis: M3U8Analysis
        if masterAnalysis.isMasterPlaylist, let firstVariant = extractVariantURLs(from: masterAnalysis.rawContent, base: masterURL).first {
            mediaAnalysis = try await analyzeM3U8(url: firstVariant)
        } else {
            mediaAnalysis = masterAnalysis
        }

        // 2단계: Init 세그먼트 분석 (EXT-X-MAP이 있으면)
        var initSegmentAnalysis: SegmentAnalysis?
        if let initURI = mediaAnalysis.extXMapURI {
            let initURL: URL
            if initURI.hasPrefix("http") {
                initURL = URL(string: initURI) ?? mediaAnalysis.sampleSegmentURLs.first ?? masterURL
            } else {
                // 상대 URL — 미디어 플레이리스트 기본 URL 기준
                let baseURL = mediaAnalysis.sampleSegmentURLs.first?.deletingLastPathComponent()
                    ?? masterURL.deletingLastPathComponent()
                initURL = baseURL.appendingPathComponent(initURI)
            }
            initSegmentAnalysis = try? await analyzeSegment(url: initURL)
        }

        // 3단계: 미디어 세그먼트 분석 (최대 3개)
        var segmentAnalyses: [SegmentAnalysis] = []
        for segURL in mediaAnalysis.sampleSegmentURLs.prefix(3) {
            if let analysis = try? await analyzeSegment(url: segURL) {
                segmentAnalyses.append(analysis)
            }
        }

        // 4단계: 프록시 바이패스 가능성 판정
        let feasibility = assessBypassFeasibility(
            m3u8: mediaAnalysis,
            initSegment: initSegmentAnalysis,
            segments: segmentAnalyses
        )

        let result = StreamDiagnosticResult(
            m3u8: mediaAnalysis,
            segments: segmentAnalyses,
            initSegment: initSegmentAnalysis,
            proxyBypassFeasibility: feasibility,
            timestamp: Date()
        )

        logger.info("[Diagnostic] Complete:\n\(result.summary)")
        return result
    }

    // MARK: - M3U8 Analysis

    /// M3U8 다운로드 및 분석
    public func analyzeM3U8(url: URL) async throws -> M3U8Analysis {
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiagnosticError.httpError(-1)
        }

        guard httpResponse.statusCode == 200 else {
            throw DiagnosticError.httpError(httpResponse.statusCode)
        }

        let content = String(data: data, encoding: .utf8) ?? ""
        guard content.contains("#EXTM3U") else {
            throw DiagnosticError.notM3U8
        }

        let isMaster = content.contains("#EXT-X-STREAM-INF")
        let hasExtXMap = content.contains("#EXT-X-MAP")
        let extXMapURI = extractExtXMapURI(from: content)
        let version = extractVersion(from: content)
        let extensions = extractSegmentExtensions(from: content)
        let segURLs = extractSegmentURLs(from: content, base: url)

        return M3U8Analysis(
            hasExtXMap: hasExtXMap,
            extXMapURI: extXMapURI,
            version: version,
            segmentExtensions: extensions,
            sampleSegmentURLs: Array(segURLs.prefix(5)),
            rawContent: content,
            isMasterPlaylist: isMaster
        )
    }

    // MARK: - Segment Analysis

    /// 세그먼트 다운로드 및 magic bytes 분석
    public func analyzeSegment(url: URL) async throws -> SegmentAnalysis {
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiagnosticError.httpError(-1)
        }
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

        let (format, boxType) = detectFormat(data: data)
        let mismatch = isMismatch(contentType: contentType, format: format)

        return SegmentAnalysis(
            contentType: contentType,
            httpStatusCode: httpResponse.statusCode,
            actualFormat: format,
            magicBytes: Array(data.prefix(16)),
            contentTypeMismatch: mismatch,
            dataSize: data.count,
            isobmffBoxType: boxType
        )
    }

    // MARK: - Format Detection

    /// 첫 8+ 바이트로 실제 포맷 감지 (VLC StreamFormat probing과 동일 로직)
    private func detectFormat(data: Data) -> (SegmentFormat, String?) {
        guard data.count >= 8 else {
            return (.insufficientData, nil)
        }

        // ISO BMFF: offset 4~7에 박스 타입 (ftyp, moov, moof, styp)
        let boxTypeBytes = data[4..<8]
        if let boxType = String(data: boxTypeBytes, encoding: .ascii) {
            switch boxType {
            case "ftyp", "moov", "moof", "styp":
                return (.fMP4(boxType: boxType), boxType)
            default:
                break
            }
        }

        // MPEG-2 TS: 0x47 sync byte
        if data[0] == 0x47 {
            // 추가 확인: 188바이트 후에도 0x47이면 확실한 TS
            if data.count >= 189 && data[188] == 0x47 {
                return (.mpegTS, nil)
            }
            // 단일 0x47만으로는 TS 추정
            return (.mpegTS, nil)
        }

        // emsg, prft 등 비표준 시작 박스
        if let boxType = String(data: boxTypeBytes, encoding: .ascii) {
            return (.unknown("box=\(boxType)"), boxType)
        }

        let hex = data.prefix(4).map { String(format: "%02X", $0) }.joined()
        return (.unknown("hex=\(hex)"), nil)
    }

    /// Content-Type과 실제 포맷의 불일치 판정
    private func isMismatch(contentType: String, format: SegmentFormat) -> Bool {
        let lower = contentType.lowercased()
        switch format {
        case .fMP4:
            // fMP4인데 Content-Type이 mp2t, octet-stream, quicktime이면 불일치
            return lower.contains("mp2t") || lower.contains("octet-stream") || lower.contains("quicktime")
        case .mpegTS:
            // TS인데 Content-Type이 mp4이면 불일치
            return lower.contains("mp4") && !lower.contains("mp2t")
        default:
            return false
        }
    }

    // MARK: - Bypass Feasibility Assessment

    /// 프록시 바이패스 가능성 종합 판정
    private func assessBypassFeasibility(
        m3u8: M3U8Analysis,
        initSegment: SegmentAnalysis?,
        segments: [SegmentAnalysis]
    ) -> ProxyBypassFeasibility {
        var reasons: [String] = []
        var risks: [String] = []
        var score = 0  // 양수 = 바이패스 유리, 음수 = 프록시 유지

        // 1) EXT-X-MAP 존재 여부 (가장 중요)
        if m3u8.hasExtXMap {
            reasons.append("EXT-X-MAP present → VLC manifest-level format detection (MP4)")
            score += 3
        } else {
            risks.append("EXT-X-MAP absent → VLC relies on probing or Content-Type fallback")
            score -= 3
        }

        // 2) 세그먼트가 fMP4인지 + probing 가능 여부
        let fmp4Segments = segments.filter {
            if case .fMP4 = $0.actualFormat { return true }
            return false
        }
        if !segments.isEmpty && fmp4Segments.count == segments.count {
            reasons.append("All segments are fMP4 → VLC probing can detect (styp/moof)")
            score += 2
        } else if !fmp4Segments.isEmpty {
            risks.append("Mixed segment formats detected")
            score -= 1
        }

        // 3) Content-Type 불일치 여부
        let mismatchSegments = segments.filter(\.contentTypeMismatch)
        if !mismatchSegments.isEmpty {
            risks.append("Content-Type mismatch detected in \(mismatchSegments.count)/\(segments.count) segments")
            if !m3u8.hasExtXMap {
                score -= 2  // EXT-X-MAP 없으면 치명적
            }
        }

        // 4) Init 세그먼트 Content-Type
        if let initSeg = initSegment {
            if initSeg.contentTypeMismatch {
                risks.append("Init segment Content-Type mismatch (may affect VLC init parsing)")
            }
        }

        // 5) VLC http-referrer 비전파 이슈 (#24622)
        risks.append("VLC Issue #24622: :http-referrer may not propagate to HLS chunk requests")

        // 판정
        let feasible = score > 0
        let confidence: ProxyBypassFeasibility.Confidence
        switch score {
        case 4...: confidence = .high
        case 2...3: confidence = .medium
        case 0...1: confidence = .low
        default: confidence = .notFeasible
        }

        return ProxyBypassFeasibility(
            feasible: feasible,
            confidence: confidence,
            reasons: reasons,
            risks: risks
        )
    }

    // MARK: - Helpers

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
        request.setValue(CommonHeaders.chzzkOrigin, forHTTPHeaderField: "Origin")
        return request
    }

    private func extractVersion(from content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#EXT-X-VERSION:") {
                let value = line.replacingOccurrences(of: "#EXT-X-VERSION:", with: "")
                return Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func extractExtXMapURI(from content: String) -> String? {
        // #EXT-X-MAP:URI="init.mp4" 또는 #EXT-X-MAP:URI="init.mp4",BYTERANGE="..."
        let lines = content.components(separatedBy: .newlines)
        for line in lines where line.contains("#EXT-X-MAP") {
            if let uriRange = line.range(of: #"URI="([^"]+)""#, options: .regularExpression) {
                let match = String(line[uriRange])
                // URI="xxx" → xxx 추출
                return String(match.dropFirst(5).dropLast(1))
            }
        }
        return nil
    }

    private func extractSegmentExtensions(from content: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var extensions = Set<String>()
        for line in lines where !line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cleanLine = line.trimmingCharacters(in: .whitespaces)
            // 쿼리 파라미터 제거
            let pathPart = cleanLine.components(separatedBy: "?").first ?? cleanLine
            if let url = URL(string: pathPart) {
                let ext = url.pathExtension
                if !ext.isEmpty {
                    extensions.insert(ext)
                }
            }
        }
        return Array(extensions).sorted()
    }

    private func extractSegmentURLs(from content: String, base: URL) -> [URL] {
        let lines = content.components(separatedBy: .newlines)
        var urls: [URL] = []
        for line in lines where !line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cleanLine = line.trimmingCharacters(in: .whitespaces)
            if let url = URL(string: cleanLine) {
                if url.host != nil {
                    urls.append(url)  // 절대 URL
                } else {
                    // 상대 URL
                    urls.append(base.deletingLastPathComponent().appendingPathComponent(cleanLine))
                }
            }
        }
        return urls
    }

    private func extractVariantURLs(from content: String, base: URL) -> [URL] {
        let lines = content.components(separatedBy: .newlines)
        var urls: [URL] = []
        var nextIsVariant = false
        for line in lines {
            if line.contains("#EXT-X-STREAM-INF") {
                nextIsVariant = true
                continue
            }
            if nextIsVariant {
                let cleanLine = line.trimmingCharacters(in: .whitespaces)
                if !cleanLine.isEmpty && !cleanLine.hasPrefix("#") {
                    if let url = URL(string: cleanLine) {
                        if url.host != nil {
                            urls.append(url)
                        } else {
                            urls.append(base.deletingLastPathComponent().appendingPathComponent(cleanLine))
                        }
                    }
                }
                nextIsVariant = false
            }
        }
        return urls
    }
}

// MARK: - Diagnostic Error

public enum DiagnosticError: Error, LocalizedError, Sendable {
    case httpError(Int)
    case notM3U8
    case noSegments

    public var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .notM3U8: return "Response is not a valid M3U8 playlist"
        case .noSegments: return "No segments found in M3U8"
        }
    }
}
