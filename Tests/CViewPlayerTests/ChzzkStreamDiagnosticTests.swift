// MARK: - ChzzkStreamDiagnosticTests.swift
// CViewPlayer - Chzzk 스트림 진단 모델 및 유틸리티 테스트

import Testing
import Foundation
@testable import CViewPlayer
@testable import CViewCore

// MARK: - SegmentFormat Tests

@Suite("SegmentFormat")
struct SegmentFormatTests {

    @Test("fMP4 description 포맷")
    func fmp4Description() {
        let format = SegmentFormat.fMP4(boxType: "styp")
        #expect(format.description == "fMP4 (ISO BMFF, box=styp)")
    }

    @Test("mpegTS description")
    func mpegTSDescription() {
        #expect(SegmentFormat.mpegTS.description == "MPEG-2 TS")
    }

    @Test("unknown description")
    func unknownDescription() {
        let format = SegmentFormat.unknown("hex=1A2B3C4D")
        #expect(format.description.contains("Unknown"))
        #expect(format.description.contains("hex=1A2B3C4D"))
    }

    @Test("insufficientData description")
    func insufficientDataDescription() {
        #expect(SegmentFormat.insufficientData.description == "Insufficient data")
    }

    @Test("vlcProbingWouldDetect — fMP4 → true")
    func vlcProbingFMP4() {
        #expect(SegmentFormat.fMP4(boxType: "moof").vlcProbingWouldDetect == true)
    }

    @Test("vlcProbingWouldDetect — mpegTS → true")
    func vlcProbingTS() {
        #expect(SegmentFormat.mpegTS.vlcProbingWouldDetect == true)
    }

    @Test("vlcProbingWouldDetect — unknown → false")
    func vlcProbingUnknown() {
        #expect(SegmentFormat.unknown("?").vlcProbingWouldDetect == false)
    }

    @Test("vlcProbingWouldDetect — insufficientData → false")
    func vlcProbingInsufficient() {
        #expect(SegmentFormat.insufficientData.vlcProbingWouldDetect == false)
    }
}

// MARK: - M3U8Analysis Tests

@Suite("M3U8Analysis")
struct M3U8AnalysisTests {

    @Test("summary — Master Playlist with EXT-X-MAP")
    func summaryMasterWithMap() {
        let analysis = M3U8Analysis(
            hasExtXMap: true,
            extXMapURI: "init.mp4",
            version: 6,
            segmentExtensions: ["m4s"],
            sampleSegmentURLs: [URL(string: "https://cdn.example.com/seg1.m4s")!],
            rawContent: "#EXTM3U\n#EXT-X-STREAM-INF:...",
            isMasterPlaylist: true
        )
        let summary = analysis.summary
        #expect(summary.contains("Master"))
        #expect(summary.contains("Version: 6"))
        #expect(summary.contains("✅ YES"))
        #expect(summary.contains("init.mp4"))
        #expect(summary.contains("m4s"))
    }

    @Test("summary — Media Playlist without EXT-X-MAP")
    func summaryMediaNoMap() {
        let analysis = M3U8Analysis(
            hasExtXMap: false,
            extXMapURI: nil,
            version: 3,
            segmentExtensions: ["ts"],
            sampleSegmentURLs: [],
            rawContent: "#EXTM3U\n#EXTINF:4.0,\nseg.ts",
            isMasterPlaylist: false
        )
        let summary = analysis.summary
        #expect(summary.contains("Media"))
        #expect(summary.contains("❌ NO"))
        #expect(summary.contains("ts"))
    }

    @Test("summary — 빈 확장자 목록")
    func summaryNoExtensions() {
        let analysis = M3U8Analysis(
            hasExtXMap: false, extXMapURI: nil, version: 0,
            segmentExtensions: [], sampleSegmentURLs: [],
            rawContent: "", isMasterPlaylist: false
        )
        #expect(analysis.summary.contains("(none)"))
    }
}

// MARK: - SegmentAnalysis Tests

@Suite("SegmentAnalysis")
struct SegmentAnalysisTests {

    @Test("summary — fMP4 세그먼트, 일치")
    func summaryFMP4() {
        let analysis = SegmentAnalysis(
            contentType: "video/mp4",
            httpStatusCode: 200,
            actualFormat: .fMP4(boxType: "moof"),
            magicBytes: [0x00, 0x00, 0x00, 0x1C, 0x6D, 0x6F, 0x6F, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            contentTypeMismatch: false,
            dataSize: 65536,
            isobmffBoxType: "moof"
        )
        let summary = analysis.summary
        #expect(summary.contains("200"))
        #expect(summary.contains("video/mp4"))
        #expect(summary.contains("fMP4"))
        #expect(summary.contains("moof"))
        #expect(summary.contains("65536"))
        #expect(summary.contains("✅ NO"))
    }

    @Test("summary — Content-Type 불일치")
    func summaryMismatch() {
        let analysis = SegmentAnalysis(
            contentType: "video/mp2t",
            httpStatusCode: 200,
            actualFormat: .fMP4(boxType: "styp"),
            magicBytes: [0x00, 0x00, 0x00, 0x18, 0x73, 0x74, 0x79, 0x70],
            contentTypeMismatch: true,
            dataSize: 1024,
            isobmffBoxType: "styp"
        )
        #expect(analysis.summary.contains("⚠️ YES"))
    }
}

// MARK: - ProxyBypassFeasibility Tests

@Suite("ProxyBypassFeasibility")
struct ProxyBypassFeasibilityTests {

    @Test("summary — feasible HIGH")
    func summaryFeasibleHigh() {
        let f = ProxyBypassFeasibility(
            feasible: true,
            confidence: .high,
            reasons: ["EXT-X-MAP present", "All fMP4"],
            risks: ["VLC #24622"]
        )
        let summary = f.summary
        #expect(summary.contains("✅ YES"))
        #expect(summary.contains("HIGH"))
        #expect(summary.contains("EXT-X-MAP present"))
        #expect(summary.contains("⚠️"))
    }

    @Test("summary — not feasible")
    func summaryNotFeasible() {
        let f = ProxyBypassFeasibility(
            feasible: false,
            confidence: .notFeasible,
            reasons: [],
            risks: ["No EXT-X-MAP"]
        )
        #expect(f.summary.contains("❌ NO"))
        #expect(f.summary.contains("NOT_FEASIBLE"))
    }

    @Test("Confidence rawValues")
    func confidenceRawValues() {
        #expect(ProxyBypassFeasibility.Confidence.high.rawValue == "HIGH")
        #expect(ProxyBypassFeasibility.Confidence.medium.rawValue == "MEDIUM")
        #expect(ProxyBypassFeasibility.Confidence.low.rawValue == "LOW")
        #expect(ProxyBypassFeasibility.Confidence.notFeasible.rawValue == "NOT_FEASIBLE")
    }
}

// MARK: - StreamDiagnosticResult Tests

@Suite("StreamDiagnosticResult")
struct StreamDiagnosticResultTests {

    @Test("summary 포맷 확인")
    func summaryFormat() {
        let m3u8 = M3U8Analysis(
            hasExtXMap: true, extXMapURI: "init.mp4", version: 6,
            segmentExtensions: ["m4s"], sampleSegmentURLs: [],
            rawContent: "", isMasterPlaylist: false
        )
        let initSeg = SegmentAnalysis(
            contentType: "video/mp4", httpStatusCode: 200,
            actualFormat: .fMP4(boxType: "ftyp"),
            magicBytes: [0x00, 0x00, 0x00, 0x00, 0x66, 0x74, 0x79, 0x70],
            contentTypeMismatch: false, dataSize: 512, isobmffBoxType: "ftyp"
        )
        let feasibility = ProxyBypassFeasibility(
            feasible: true, confidence: .high,
            reasons: ["Test"], risks: []
        )
        let result = StreamDiagnosticResult(
            m3u8: m3u8,
            segments: [],
            initSegment: initSeg,
            proxyBypassFeasibility: feasibility,
            timestamp: Date()
        )
        let summary = result.summary
        #expect(summary.contains("Chzzk Stream Diagnostic Report"))
        #expect(summary.contains("Init Segment"))
        #expect(summary.contains("Proxy Bypass Feasibility"))
    }
}

// MARK: - DiagnosticError Tests

@Suite("DiagnosticError")
struct DiagnosticErrorTests {

    @Test("errorDescription — httpError")
    func httpError() {
        let err = DiagnosticError.httpError(403)
        #expect(err.errorDescription == "HTTP 403")
    }

    @Test("errorDescription — notM3U8")
    func notM3U8() {
        let err = DiagnosticError.notM3U8
        #expect(err.errorDescription?.contains("M3U8") == true)
    }

    @Test("errorDescription — noSegments")
    func noSegments() {
        let err = DiagnosticError.noSegments
        #expect(err.errorDescription?.contains("segments") == true)
    }
}
