// MARK: - CViewPlayerTests.swift
// CViewPlayer module tests

import Testing
import Foundation
@testable import CViewPlayer
@testable import CViewCore

// MARK: - HLS Manifest Parser Tests

@Suite("HLSManifestParser")
struct HLSManifestParserTests {
    
    let parser = HLSManifestParser()
    
    @Test("Parse master playlist")
    func parseMaster() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.64001f,mp4a.40.2",FRAME-RATE=30.0,NAME="1080p"
        1080p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",FRAME-RATE=30.0,NAME="720p"
        720p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,CODECS="avc1.64001f,mp4a.40.2",FRAME-RATE=30.0,NAME="480p"
        480p/playlist.m3u8
        """
        
        let baseURL = URL(string: "https://example.com/live/master.m3u8")!
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        
        #expect(playlist.variants.count == 3)
        #expect(playlist.variants[0].bandwidth == 5_000_000) // Sorted descending
        #expect(playlist.variants[0].resolution == "1920x1080")
        #expect(playlist.variants[0].qualityLabel == "1080p")
        #expect(playlist.variants[1].qualityLabel == "720p")
    }
    
    @Test("Parse media playlist")
    func parseMedia() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:5.005,
        segment100.ts
        #EXTINF:5.005,
        segment101.ts
        #EXTINF:4.838,
        segment102.ts
        """
        
        let baseURL = URL(string: "https://example.com/live/playlist.m3u8")!
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        
        #expect(playlist.targetDuration == 6.0)
        #expect(playlist.mediaSequence == 100)
        #expect(playlist.segments.count == 3)
        #expect(playlist.segments[0].id == 100)
        #expect(abs(playlist.segments[0].duration - 5.005) < 0.001)
        #expect(playlist.isEndList == false)
    }
    
    @Test("Parse LL-HLS extensions")
    func parseLLHLS() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:200
        #EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.0
        #EXT-X-PART-INF:PART-TARGET=0.5
        #EXTINF:4.0,
        segment200.ts
        #EXT-X-PART:DURATION=0.5,URI="part201-0.ts",INDEPENDENT=YES
        #EXT-X-PART:DURATION=0.5,URI="part201-1.ts"
        #EXT-X-PRELOAD-HINT:TYPE=PART,URI="part201-2.ts"
        """
        
        let baseURL = URL(string: "https://example.com/live/playlist.m3u8")!
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        
        #expect(playlist.isLowLatency == true)
        #expect(playlist.partTargetDuration == 0.5)
        #expect(playlist.serverControl?.canBlockReload == true)
        #expect(playlist.serverControl?.partHoldBack == 1.0)
        #expect(playlist.partialSegments.count == 2)
        #expect(playlist.partialSegments[0].independent == true)
        #expect(playlist.preloadHint?.type == "PART")
    }
    
    @Test("Parse end list")
    func parseEndList() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        segment0.ts
        #EXT-X-ENDLIST
        """
        
        let baseURL = URL(string: "https://example.com/vod.m3u8")!
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        
        #expect(playlist.isEndList == true)
    }
    
    @Test("Invalid manifest throws error")
    func invalidManifest() {
        let content = "This is not a valid M3U8"
        let baseURL = URL(string: "https://example.com/invalid.m3u8")!
        
        #expect(throws: AppError.self) {
            _ = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        }
    }
    
    @Test("Absolute URLs are preserved")
    func absoluteURLs() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        https://cdn.example.com/1080p/playlist.m3u8
        """
        
        let baseURL = URL(string: "https://origin.example.com/master.m3u8")!
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        
        #expect(playlist.variants[0].uri.absoluteString == "https://cdn.example.com/1080p/playlist.m3u8")
    }
    
    @Test("Total duration calculated correctly")
    func totalDuration() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        #EXTINF:3.5,
        seg1.ts
        #EXTINF:4.0,
        seg2.ts
        """
        
        let baseURL = URL(string: "https://example.com/playlist.m3u8")!
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        
        #expect(abs(playlist.totalDuration - 11.5) < 0.001)
    }
}

// MARK: - ABR Controller Tests

@Suite("ABRController")
struct ABRControllerTests {
    
    @Test("No switch when no levels set")
    func noLevels() async {
        let abr = ABRController()
        let decision = await abr.recommendLevel()
        #expect(decision == .maintain)
    }
    
    @Test("Initial selection uses initial bandwidth estimate")
    func initialSelection() async {
        let abr = ABRController(configuration: .default)
        
        let variants: [MasterPlaylist.Variant] = [
            .init(bandwidth: 1_000_000, averageBandwidth: nil, resolution: "640x360", codecs: nil, frameRate: nil, uri: URL(string: "https://example.com/360p.m3u8")!, name: "360p"),
            .init(bandwidth: 3_000_000, averageBandwidth: nil, resolution: "1280x720", codecs: nil, frameRate: nil, uri: URL(string: "https://example.com/720p.m3u8")!, name: "720p"),
            .init(bandwidth: 5_000_000, averageBandwidth: nil, resolution: "1920x1080", codecs: nil, frameRate: nil, uri: URL(string: "https://example.com/1080p.m3u8")!, name: "1080p"),
        ]
        
        await abr.setLevels(variants)
        
        let selected = await abr.selectedLevel
        #expect(selected != nil)
    }
    
    @Test("Bandwidth sample recording")
    func recordSample() async {
        let abr = ABRController()
        
        let sample = ABRController.BandwidthSample(
            bytesLoaded: 1_000_000,
            duration: 1.0
        )
        
        await abr.recordSample(sample)
        
        let estimate = await abr.currentBandwidthEstimate()
        #expect(estimate > 0)
    }
    
    @Test("Reset clears state")
    func resetABR() async {
        let abr = ABRController()
        
        let sample = ABRController.BandwidthSample(bytesLoaded: 1_000_000, duration: 1.0)
        await abr.recordSample(sample)
        await abr.reset()
        
        let estimate = await abr.currentBandwidthEstimate()
        // Should return initial bandwidth estimate after reset
        #expect(estimate == Double(ABRController.Configuration.default.initialBandwidthEstimate))
    }
}

// MARK: - StreamQuality Tests

@Suite("StreamQuality")
struct StreamQualityTests {
    
    @Test("Quality enum equality")
    func equality() {
        let q1 = StreamQuality.source
        let q2 = StreamQuality.source
        #expect(q1 == q2)
    }
    
    @Test("Quality raw values")
    func rawValues() {
        #expect(StreamQuality.auto.rawValue == "auto")
        #expect(StreamQuality.source.rawValue == "1080p")
        #expect(StreamQuality.high.rawValue == "720p")
        #expect(StreamQuality.medium.rawValue == "480p")
        #expect(StreamQuality.low.rawValue == "360p")
    }
    
    @Test("All cases available")
    func allCases() {
        #expect(StreamQuality.allCases.count == 5)
    }
    
    @Test("Display name is set")
    func displayName() {
        #expect(StreamQuality.auto.displayName.isEmpty == false)
        #expect(StreamQuality.source.displayName.contains("1080"))
    }
}
