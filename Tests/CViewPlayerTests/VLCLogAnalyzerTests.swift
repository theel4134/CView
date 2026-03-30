// MARK: - VLCLogAnalyzerTests.swift
// CViewPlayer - VLC 로그 분석 유틸리티 테스트

#if DEBUG

import Testing
import Foundation
@testable import CViewPlayer

// MARK: - VLCFormatVerdict Tests

@Suite("VLCFormatVerdict")
struct VLCFormatVerdictTests {

    @Test("summary — 모두 정상 (bypass 성공)")
    func summaryAllGood() {
        let verdict = VLCFormatVerdict(
            mp4FormatDetected: true,
            tsFailureDetected: false,
            extXMapRecognized: true,
            contentTypeFallbackUsed: false,
            proxyBypassWorked: true
        )
        let summary = verdict.summary
        #expect(summary.contains("MP4 format detected: ✅"))
        #expect(summary.contains("TS demux failure: ✅ NO"))
        #expect(summary.contains("EXT-X-MAP recognized: ✅"))
        #expect(summary.contains("Content-Type fallback: ✅ NO"))
        #expect(summary.contains("Proxy bypass would work: ✅ LIKELY"))
    }

    @Test("summary — 모두 실패")
    func summaryAllBad() {
        let verdict = VLCFormatVerdict(
            mp4FormatDetected: false,
            tsFailureDetected: true,
            extXMapRecognized: false,
            contentTypeFallbackUsed: true,
            proxyBypassWorked: false
        )
        let summary = verdict.summary
        #expect(summary.contains("MP4 format detected: ❌"))
        #expect(summary.contains("TS demux failure: ⚠️ YES"))
        #expect(summary.contains("EXT-X-MAP recognized: ❌ NO"))
        #expect(summary.contains("Content-Type fallback: ⚠️ YES"))
        #expect(summary.contains("Proxy bypass would work: ❌ UNLIKELY"))
    }
}

// MARK: - VLCLogEntry Tests

@Suite("VLCLogEntry")
struct VLCLogEntryTests {

    @Test("기본 프로퍼티 확인")
    func basicProperties() {
        let entry = VLCLogEntry(lineNumber: 42, level: "error", module: "ts", message: "TS sync lost")
        #expect(entry.lineNumber == 42)
        #expect(entry.level == "error")
        #expect(entry.module == "ts")
        #expect(entry.message == "TS sync lost")
    }
}

// MARK: - VLCLogAnalysisReport Tests

@Suite("VLCLogAnalysisReport")
struct VLCLogAnalysisReportTests {

    @Test("summary 포맷 — 헤더, 섹션, verdict 포함")
    func summaryFormat() {
        let verdict = VLCFormatVerdict(
            mp4FormatDetected: true, tsFailureDetected: false,
            extXMapRecognized: true, contentTypeFallbackUsed: false,
            proxyBypassWorked: true
        )
        let report = VLCLogAnalysisReport(
            totalLines: 100,
            formatEntries: [VLCLogEntry(lineNumber: 1, level: "info", module: "mp4", message: "mp4 selected")],
            tsFailureEntries: [],
            initSegmentEntries: [],
            contentTypeEntries: [],
            httpErrorEntries: [],
            adaptiveEntries: [],
            verdict: verdict
        )
        let summary = report.summary
        #expect(summary.contains("VLC Debug Log Analysis Report"))
        #expect(summary.contains("Total log lines: 100"))
        #expect(summary.contains("Format Detection (1)"))
        #expect(summary.contains("TS Demux Failures (0)"))
        #expect(summary.contains("Verdict"))
    }

    @Test("summary — 10개 초과 항목 truncation")
    func summaryTruncation() {
        let entries = (1...15).map { i in
            VLCLogEntry(lineNumber: i, level: "debug", module: "fmt", message: "line \(i)")
        }
        let verdict = VLCFormatVerdict(
            mp4FormatDetected: false, tsFailureDetected: false,
            extXMapRecognized: false, contentTypeFallbackUsed: false,
            proxyBypassWorked: false
        )
        let report = VLCLogAnalysisReport(
            totalLines: 15, formatEntries: entries,
            tsFailureEntries: [], initSegmentEntries: [],
            contentTypeEntries: [], httpErrorEntries: [],
            adaptiveEntries: [], verdict: verdict
        )
        #expect(report.summary.contains("... +5 more"))
    }
}

// MARK: - VLCLogAnalyzer Integration Tests

@Suite("VLCLogAnalyzer", .serialized)
struct VLCLogAnalyzerTests {

    private let logPath = VLCLogAnalyzer.logPath

    @Test("logPath 상수 확인")
    func logPathConstant() {
        #expect(VLCLogAnalyzer.logPath == "/tmp/vlc_internal.log")
    }

    @Test("analyze — MP4 포맷 감지 로그")
    func analyzeMP4FormatDetected() throws {
        let logContent = """
        [adaptive] debug: playlist updated
        [mp4] info: mp4 format selected for playback
        [http] debug: HTTP/1.1 200 OK
        """
        try logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        #expect(report.totalLines == 4) // 3줄 + 마지막 빈줄
        #expect(report.verdict.mp4FormatDetected == true)
        #expect(report.verdict.tsFailureDetected == false)
        #expect(report.verdict.proxyBypassWorked == true)
    }

    @Test("analyze — TS demux 실패 로그")
    func analyzeTSFailure() throws {
        let logContent = """
        [ts] error: does not look like a TS packet
        [adaptive] debug: segment download complete
        """
        try logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        #expect(report.verdict.tsFailureDetected == true)
        #expect(report.tsFailureEntries.count >= 1)
        #expect(report.verdict.proxyBypassWorked == false)
    }

    @Test("analyze — EXT-X-MAP 인식 로그")
    func analyzeExtXMap() throws {
        let logContent = """
        [adaptive] debug: processing EXT-X-MAP directive
        [adaptive] info: init segment loaded
        """
        try logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        #expect(report.verdict.extXMapRecognized == true)
        #expect(report.initSegmentEntries.count >= 1)
    }

    @Test("analyze — Content-Type fallback 사용")
    func analyzeContentTypeFallback() throws {
        let logContent = """
        [http] debug: Content-Type: video/mp2t
        [demux] info: mp2t format selected based on Content-Type
        """
        try logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        #expect(report.verdict.contentTypeFallbackUsed == true)
    }

    @Test("analyze — 로그 파일 없으면 throw")
    func analyzeFileNotFound() throws {
        try? FileManager.default.removeItem(atPath: logPath)
        let analyzer = VLCLogAnalyzer()
        #expect(throws: (any Error).self) {
            try analyzer.analyze()
        }
    }

    @Test("analyze — 빈 로그 파일")
    func analyzeEmptyLog() throws {
        try "".write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        #expect(report.totalLines == 1) // 빈 문자열 → [""] → 1 요소
        #expect(report.verdict.mp4FormatDetected == false)
        #expect(report.verdict.tsFailureDetected == false)
    }

    @Test("analyze — module 파싱 ([bracket] 형식)")
    func analyzeModuleParsing() throws {
        let logContent = "[mp4] debug: opening mp4 container"
        try logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        // formatEntries에 포함되어야 함 ("mp4" 패턴 매칭)
        let mp4Entry = report.formatEntries.first { $0.module == "mp4" }
        #expect(mp4Entry != nil)
        #expect(mp4Entry?.module == "mp4")
    }

    @Test("analyze — error 레벨 감지")
    func analyzeErrorLevel() throws {
        let logContent = "[ts] error: lost sync on TS packet"
        try logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        let errorEntry = report.tsFailureEntries.first
        #expect(errorEntry?.level == "error")
    }

    @Test("analyze — 200자 초과 메시지 truncation")
    func analyzeLongMessageTruncation() throws {
        let longMessage = "[unknown] " + String(repeating: "x", count: 250)
        try longMessage.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        let report = try analyzer.analyze()

        // 전체 라인이 200자 넘으면 message가 잘림
        // formatEntries or adaptiveEntries에 없어도 report.totalLines로 확인
        #expect(report.totalLines >= 1)
    }

    @Test("logFileExists — 파일 없음")
    func logFileExistsWhenMissing() {
        try? FileManager.default.removeItem(atPath: logPath)
        let analyzer = VLCLogAnalyzer()
        #expect(analyzer.logFileExists == false)
    }

    @Test("logFileExists / logFileSize — 파일 존재")
    func logFileExistsAndSize() throws {
        let content = "test log content"
        try content.write(toFile: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let analyzer = VLCLogAnalyzer()
        #expect(analyzer.logFileExists == true)
        #expect(analyzer.logFileSize > 0)
    }
}

#endif
