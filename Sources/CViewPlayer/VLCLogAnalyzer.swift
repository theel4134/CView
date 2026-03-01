// MARK: - VLCLogAnalyzer.swift
// CViewPlayer - VLC 내부 디버그 로그 분석 유틸리티
//
// VLC 재생 엔진의 /tmp/vlc_internal.log 파일을 분석하여
// 포맷 결정 과정, Content-Type 문제, demux 실패를 진단합니다.
//
// 참조: VLC_DIRECT_PLAYBACK_RESEARCH.md §3.5, §8.3
//
// 사용:
//   let analyzer = VLCLogAnalyzer()
//   let report = try analyzer.analyze()
//   print(report.summary)

#if DEBUG

import Foundation
import CViewCore

// MARK: - Analysis Models

/// VLC 로그 분석 결과
public struct VLCLogAnalysisReport: Sendable {
    /// 분석한 로그 라인 수
    public let totalLines: Int
    /// 포맷 결정 관련 로그
    public let formatEntries: [VLCLogEntry]
    /// TS demux 실패 로그
    public let tsFailureEntries: [VLCLogEntry]
    /// EXT-X-MAP / init segment 관련 로그
    public let initSegmentEntries: [VLCLogEntry]
    /// Content-Type 관련 로그
    public let contentTypeEntries: [VLCLogEntry]
    /// HTTP 오류 로그
    public let httpErrorEntries: [VLCLogEntry]
    /// adaptive 모듈 로그
    public let adaptiveEntries: [VLCLogEntry]
    /// 분석 판정
    public let verdict: VLCFormatVerdict

    public var summary: String {
        var lines: [String] = []
        lines.append("╔══════════════════════════════════════════╗")
        lines.append("║  VLC Debug Log Analysis Report            ║")
        lines.append("╚══════════════════════════════════════════╝")
        lines.append("")
        lines.append("Total log lines: \(totalLines)")
        lines.append("")

        func section(_ title: String, _ entries: [VLCLogEntry]) {
            lines.append("── \(title) (\(entries.count)) ──")
            for entry in entries.prefix(10) {
                lines.append("  L\(entry.lineNumber): [\(entry.module)] \(entry.message)")
            }
            if entries.count > 10 {
                lines.append("  ... +\(entries.count - 10) more")
            }
            lines.append("")
        }

        section("Format Detection", formatEntries)
        section("TS Demux Failures", tsFailureEntries)
        section("Init Segment / EXT-X-MAP", initSegmentEntries)
        section("Content-Type", contentTypeEntries)
        section("HTTP Errors", httpErrorEntries)
        section("Adaptive Module", adaptiveEntries)

        lines.append("── Verdict ──")
        lines.append(verdict.summary)

        return lines.joined(separator: "\n")
    }
}

/// 개별 로그 항목
public struct VLCLogEntry: Sendable {
    public let lineNumber: Int
    public let level: String     // debug, warning, error
    public let module: String    // adaptive, ts, mp4, http, etc.
    public let message: String
}

/// 포맷 결정 판정
public struct VLCFormatVerdict: Sendable {
    /// VLC가 MP4 포맷을 성공적으로 인식했는지
    public let mp4FormatDetected: Bool
    /// TS demux 실패가 발생했는지
    public let tsFailureDetected: Bool
    /// EXT-X-MAP이 인식되었는지
    public let extXMapRecognized: Bool
    /// Content-Type fallback이 사용되었는지
    public let contentTypeFallbackUsed: Bool
    /// 프록시 없이 재생 가능했는지 (추정)
    public let proxyBypassWorked: Bool

    public var summary: String {
        var lines: [String] = []
        lines.append("MP4 format detected: \(mp4FormatDetected ? "✅" : "❌")")
        lines.append("TS demux failure: \(tsFailureDetected ? "⚠️ YES" : "✅ NO")")
        lines.append("EXT-X-MAP recognized: \(extXMapRecognized ? "✅" : "❌ NO")")
        lines.append("Content-Type fallback: \(contentTypeFallbackUsed ? "⚠️ YES" : "✅ NO")")
        lines.append("Proxy bypass would work: \(proxyBypassWorked ? "✅ LIKELY" : "❌ UNLIKELY")")
        return lines.joined(separator: "\n")
    }
}

// MARK: - VLC Log Analyzer

/// VLC 내부 로그 (/tmp/vlc_internal.log) 분석기
public struct VLCLogAnalyzer: Sendable {

    /// VLC 로그 파일 경로
    public static let logPath = "/tmp/vlc_internal.log"

    private let logger = AppLogger.player

    public init() {}

    /// 로그 파일 분석 실행
    public func analyze() throws -> VLCLogAnalysisReport {
        let content = try String(contentsOfFile: Self.logPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var formatEntries: [VLCLogEntry] = []
        var tsFailureEntries: [VLCLogEntry] = []
        var initSegmentEntries: [VLCLogEntry] = []
        var contentTypeEntries: [VLCLogEntry] = []
        var httpErrorEntries: [VLCLogEntry] = []
        var adaptiveEntries: [VLCLogEntry] = []

        // 패턴 매칭: VLC 로그에서 관심 있는 키워드 추출
        let formatPatterns = [
            "StreamFormat", "format", "demux", "mp4", "mp2t",
            "MPEG2TS", "probing", "selected"
        ]
        let tsFailurePatterns = [
            "does not look like", "TS.*discard", "lost sync",
            "garbage", "repositioning"
        ]
        let initSegmentPatterns = [
            "init.*segment", "EXT-X-MAP", "initialization",
            "InitSegment", "init_segment"
        ]
        let contentTypePatterns = [
            "content.type", "Content-Type", "video/mp2t",
            "video/mp4", "content_type", "mime"
        ]
        let httpErrorPatterns = [
            "HTTP/1", "403", "404", "500", "access error",
            "connection refused"
        ]
        let adaptivePatterns = [
            "adaptive", "segment.*download", "playlist.*update",
            "buffering", "representation"
        ]

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let entry = parseLogEntry(line: line, lineNumber: index + 1)

            if matchesAny(lower, patterns: formatPatterns) {
                formatEntries.append(entry)
            }
            if matchesAny(lower, patterns: tsFailurePatterns) {
                tsFailureEntries.append(entry)
            }
            if matchesAny(lower, patterns: initSegmentPatterns) {
                initSegmentEntries.append(entry)
            }
            if matchesAny(lower, patterns: contentTypePatterns) {
                contentTypeEntries.append(entry)
            }
            if matchesAny(lower, patterns: httpErrorPatterns) {
                httpErrorEntries.append(entry)
            }
            if matchesAny(lower, patterns: adaptivePatterns) {
                adaptiveEntries.append(entry)
            }
        }

        // 판정
        let verdict = assessVerdict(
            formatEntries: formatEntries,
            tsFailureEntries: tsFailureEntries,
            initSegmentEntries: initSegmentEntries,
            contentTypeEntries: contentTypeEntries
        )

        let report = VLCLogAnalysisReport(
            totalLines: lines.count,
            formatEntries: formatEntries,
            tsFailureEntries: tsFailureEntries,
            initSegmentEntries: initSegmentEntries,
            contentTypeEntries: contentTypeEntries,
            httpErrorEntries: httpErrorEntries,
            adaptiveEntries: adaptiveEntries,
            verdict: verdict
        )

        // 파일 출력
        let reportPath = "/tmp/vlc_log_analysis.txt"
        try? report.summary.write(toFile: reportPath, atomically: true, encoding: .utf8)
        logger.info("[VLCLogAnalyzer] Analysis complete → \(reportPath)")

        return report
    }

    /// 로그 파일이 존재하는지 확인
    public var logFileExists: Bool {
        FileManager.default.fileExists(atPath: Self.logPath)
    }

    /// 로그 파일 크기 (bytes)
    public var logFileSize: UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: Self.logPath)[.size] as? UInt64) ?? 0
    }

    // MARK: - Private Helpers

    private func parseLogEntry(line: String, lineNumber: Int) -> VLCLogEntry {
        // VLC 로그 포맷: "[module] level: message" 또는 자유 형식
        var module = "unknown"
        var level = "debug"
        var message = line

        // [module] 추출
        if let bracketRange = line.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
            module = String(line[bracketRange]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }

        // 레벨 추출
        let lower = line.lowercased()
        if lower.contains("error") {
            level = "error"
        } else if lower.contains("warning") || lower.contains("warn") {
            level = "warning"
        } else if lower.contains("info") {
            level = "info"
        }

        // 메시지는 원본 라인 (너무 길면 잘라냄)
        if message.count > 200 {
            message = String(message.prefix(200)) + "..."
        }

        return VLCLogEntry(lineNumber: lineNumber, level: level, module: module, message: message)
    }

    private func matchesAny(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if let _ = text.range(of: pattern, options: [.caseInsensitive, .regularExpression]) {
                return true
            }
        }
        return false
    }

    private func assessVerdict(
        formatEntries: [VLCLogEntry],
        tsFailureEntries: [VLCLogEntry],
        initSegmentEntries: [VLCLogEntry],
        contentTypeEntries: [VLCLogEntry]
    ) -> VLCFormatVerdict {
        // MP4 포맷 감지 확인
        let mp4Detected = formatEntries.contains { entry in
            let lower = entry.message.lowercased()
            return (lower.contains("mp4") && lower.contains("selected"))
                || (lower.contains("format") && lower.contains("mp4"))
        }

        // TS 실패 감지
        let tsFailure = !tsFailureEntries.isEmpty

        // EXT-X-MAP 인식 확인
        let extXMap = initSegmentEntries.contains { entry in
            let lower = entry.message.lowercased()
            return lower.contains("ext-x-map") || lower.contains("init") && lower.contains("segment")
        }

        // Content-Type fallback 사용 확인
        let ctFallback = contentTypeEntries.contains { entry in
            let lower = entry.message.lowercased()
            return lower.contains("mp2t") && (lower.contains("format") || lower.contains("selected"))
        }

        // 종합 판단: 프록시 없이 재생 가능했는지
        let bypassWorked = mp4Detected && !tsFailure

        return VLCFormatVerdict(
            mp4FormatDetected: mp4Detected,
            tsFailureDetected: tsFailure,
            extXMapRecognized: extXMap,
            contentTypeFallbackUsed: ctFallback,
            proxyBypassWorked: bypassWorked
        )
    }
}

#endif
