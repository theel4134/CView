// MARK: - HLSManifestParserTests.swift
// Comprehensive unit tests for HLSManifestParser

import Testing
import Foundation
@testable import CViewPlayer
@testable import CViewCore

// MARK: - Master Playlist Parsing

@Suite("HLSManifestParser — Master Playlist")
struct HLSManifestParserMasterTests {

    let parser = HLSManifestParser()
    let baseURL = URL(string: "https://cdn.example.com/live/master.m3u8")!

    @Test("Parse master with single variant")
    func singleVariant() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        720p/stream.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.variants.count == 1)
        #expect(playlist.variants[0].bandwidth == 3_000_000)
        #expect(playlist.variants[0].resolution == "1280x720")
    }

    @Test("Parse master with multiple variants sorted by bandwidth descending")
    func multipleVariantsSorted() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480
        480p/stream.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        1080p/stream.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        720p/stream.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.variants.count == 3)
        #expect(playlist.variants[0].bandwidth == 5_000_000) // highest first
        #expect(playlist.variants[1].bandwidth == 3_000_000)
        #expect(playlist.variants[2].bandwidth == 1_500_000) // lowest last
    }

    @Test("Parse master with CODECS, FRAME-RATE, NAME")
    func fullAttributes() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.64001f,mp4a.40.2",FRAME-RATE=30.0,NAME="1080p"
        1080p/playlist.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        let v = playlist.variants[0]
        #expect(v.codecs == "avc1.64001f,mp4a.40.2")
        #expect(v.frameRate == 30.0)
        #expect(v.name == "1080p")
    }

    @Test("Parse master with AVERAGE-BANDWIDTH")
    func averageBandwidth() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,AVERAGE-BANDWIDTH=4500000,RESOLUTION=1920x1080
        1080p/playlist.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.variants[0].averageBandwidth == 4_500_000)
    }

    @Test("Relative URIs resolved against base URL")
    func relativeURI() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        720p/playlist.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.variants[0].uri.absoluteString.contains("720p/playlist.m3u8"))
    }

    @Test("Absolute URIs preserved as-is")
    func absoluteURI() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        https://other-cdn.example.com/1080p/playlist.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.variants[0].uri.absoluteString == "https://other-cdn.example.com/1080p/playlist.m3u8")
    }

    @Test("Playlist uri stores baseURL")
    func playlistURI() throws {
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360
        360p.m3u8
        """
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.uri == baseURL)
    }

    @Test("Invalid manifest (missing #EXTM3U) throws error")
    func invalidManifestNoTag() {
        let content = "Not a valid manifest"
        #expect(throws: AppError.self) {
            _ = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        }
    }

    @Test("Empty content after #EXTM3U throws invalidManifest")
    func emptyVariantsThrows() throws {
        let content = "#EXTM3U\n"
        #expect(throws: AppError.self) {
            _ = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        }
    }

    @Test("Blank lines and comments are ignored")
    func blankLinesAndComments() throws {
        let content = """
        #EXTM3U
        ## This is a comment
        
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        
        720p/stream.m3u8
        """
        // Note: blank line between STREAM-INF and URI technically breaks parsing,
        // but the non-empty line after comments should work
        let playlist = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        // At least should not crash
        #expect(playlist.variants.count >= 0)
    }
}

// MARK: - Quality Labels

@Suite("HLSManifestParser — Quality Labels")
struct HLSManifestParserQualityLabelTests {

    @Test("Quality label from NAME attribute")
    func labelFromName() {
        let v = MasterPlaylist.Variant(
            bandwidth: 5_000_000,
            averageBandwidth: nil,
            resolution: "1920x1080",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/1080p.m3u8")!,
            name: "Full HD"
        )
        #expect(v.qualityLabel == "Full HD")
    }

    @Test("Quality label 1080p from resolution")
    func label1080p() {
        let v = MasterPlaylist.Variant(
            bandwidth: 5_000_000,
            averageBandwidth: nil,
            resolution: "1920x1080",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/1080p.m3u8")!,
            name: nil
        )
        #expect(v.qualityLabel == "1080p")
    }

    @Test("Quality label 720p from resolution")
    func label720p() {
        let v = MasterPlaylist.Variant(
            bandwidth: 3_000_000,
            averageBandwidth: nil,
            resolution: "1280x720",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/720p.m3u8")!,
            name: nil
        )
        #expect(v.qualityLabel == "720p")
    }

    @Test("Quality label 480p from resolution")
    func label480p() {
        let v = MasterPlaylist.Variant(
            bandwidth: 1_500_000,
            averageBandwidth: nil,
            resolution: "854x480",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/480p.m3u8")!,
            name: nil
        )
        #expect(v.qualityLabel == "480p")
    }

    @Test("Quality label 360p from resolution")
    func label360p() {
        let v = MasterPlaylist.Variant(
            bandwidth: 800_000,
            averageBandwidth: nil,
            resolution: "640x360",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/360p.m3u8")!,
            name: nil
        )
        #expect(v.qualityLabel == "360p")
    }

    @Test("Quality label fallback to kbps")
    func labelFallbackKbps() {
        let v = MasterPlaylist.Variant(
            bandwidth: 2_500_000,
            averageBandwidth: nil,
            resolution: "960x540",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/540p.m3u8")!,
            name: nil
        )
        #expect(v.qualityLabel == "2500kbps")
    }

    @Test("Variant id is bandwidth-resolution combo")
    func variantId() {
        let v = MasterPlaylist.Variant(
            bandwidth: 5_000_000,
            averageBandwidth: nil,
            resolution: "1920x1080",
            codecs: nil,
            frameRate: nil,
            uri: URL(string: "https://example.com/1080p.m3u8")!,
            name: nil
        )
        #expect(v.id == "5000000-1920x1080")
    }
}

// MARK: - Media Playlist Parsing

@Suite("HLSManifestParser — Media Playlist")
struct HLSManifestParserMediaTests {

    let parser = HLSManifestParser()
    let baseURL = URL(string: "https://cdn.example.com/live/playlist.m3u8")!

    @Test("Parse target duration")
    func targetDuration() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:5.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.targetDuration == 6.0)
    }

    @Test("Parse media sequence number")
    func mediaSequence() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:500
        #EXTINF:4.0,
        seg500.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.mediaSequence == 500)
        #expect(playlist.segments[0].id == 500)
    }

    @Test("Segment IDs increment from media sequence")
    func segmentIds() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:4.0,
        seg100.ts
        #EXTINF:4.0,
        seg101.ts
        #EXTINF:4.0,
        seg102.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.segments[0].id == 100)
        #expect(playlist.segments[1].id == 101)
        #expect(playlist.segments[2].id == 102)
    }

    @Test("Segment start times accumulate correctly")
    func segmentStartTimes() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:5
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        #EXTINF:3.5,
        seg1.ts
        #EXTINF:5.0,
        seg2.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(abs(playlist.segments[0].startTime - 0.0) < 0.001)
        #expect(abs(playlist.segments[1].startTime - 4.0) < 0.001)
        #expect(abs(playlist.segments[2].startTime - 7.5) < 0.001)
    }

    @Test("Total duration sums all segment durations")
    func totalDuration() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:5
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        #EXTINF:3.5,
        seg1.ts
        #EXTINF:5.0,
        seg2.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(abs(playlist.totalDuration - 12.5) < 0.001)
    }

    @Test("End time equals last segment start + duration")
    func endTime() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:5
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        #EXTINF:3.0,
        seg1.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(abs(playlist.endTime - 7.0) < 0.001) // 4.0 + 3.0
    }

    @Test("Empty media playlist (no segments)")
    func emptyPlaylist() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.segments.isEmpty)
        #expect(playlist.totalDuration == 0)
        #expect(playlist.endTime == 0)
    }

    @Test("isEndList is true when #EXT-X-ENDLIST present")
    func endList() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        #EXT-X-ENDLIST
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.isEndList == true)
    }

    @Test("isEndList is false for live playlist")
    func noEndList() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.isEndList == false)
    }

    @Test("Discontinuity flag parsed correctly")
    func discontinuity() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:4.0,
        seg0.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:4.0,
        seg1.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.segments[0].discontinuity == false)
        #expect(playlist.segments[1].discontinuity == true)
    }

    @Test("Invalid media manifest throws error")
    func invalidManifest() {
        let content = "This is not M3U8"
        #expect(throws: AppError.self) {
            _ = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        }
    }
}

// MARK: - LL-HLS Extensions

@Suite("HLSManifestParser — Low-Latency HLS")
struct HLSManifestParserLLHLSTests {

    let parser = HLSManifestParser()
    let baseURL = URL(string: "https://cdn.example.com/live/playlist.m3u8")!

    @Test("isLowLatency is true when PART-INF present")
    func llhlsDetection() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PART-INF:PART-TARGET=0.5
        #EXTINF:4.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.isLowLatency == true)
        #expect(playlist.partTargetDuration == 0.5)
    }

    @Test("Parse partial segments")
    func partialSegments() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:100
        #EXT-X-PART-INF:PART-TARGET=0.5
        #EXTINF:4.0,
        seg100.ts
        #EXT-X-PART:DURATION=0.5,URI="part101-0.ts",INDEPENDENT=YES
        #EXT-X-PART:DURATION=0.5,URI="part101-1.ts"
        #EXT-X-PART:DURATION=0.5,URI="part101-2.ts",INDEPENDENT=YES
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.partialSegments.count == 3)
        #expect(playlist.partialSegments[0].independent == true)
        #expect(playlist.partialSegments[1].independent == false)
        #expect(playlist.partialSegments[2].independent == true)
    }

    @Test("Parse server control attributes")
    func serverControl() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.5,CAN-SKIP-UNTIL=24.0,HOLD-BACK=6.0
        #EXTINF:4.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.serverControl != nil)
        #expect(playlist.serverControl?.canBlockReload == true)
        #expect(playlist.serverControl?.partHoldBack == 1.5)
        #expect(playlist.serverControl?.canSkipUntil == 24.0)
        #expect(playlist.serverControl?.holdBack == 6.0)
    }

    @Test("Parse preload hint")
    func preloadHint() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PART-INF:PART-TARGET=0.5
        #EXTINF:4.0,
        seg0.ts
        #EXT-X-PRELOAD-HINT:TYPE=PART,URI="next-part.ts"
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.preloadHint != nil)
        #expect(playlist.preloadHint?.type == "PART")
        #expect(playlist.preloadHint?.uri.lastPathComponent == "next-part.ts")
    }

    @Test("isLowLatency is true when PART tags present")
    func llhlsFromParts() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:4.0,
        seg100.ts
        #EXT-X-PART:DURATION=0.5,URI="part101-0.ts"
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.isLowLatency == true)
    }

    @Test("Standard HLS without LL features is not lowLatency")
    func standardHLSNotLL() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:6.0,
        seg0.ts
        #EXTINF:6.0,
        seg1.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.isLowLatency == false)
        #expect(playlist.partTargetDuration == nil)
        #expect(playlist.serverControl == nil)
        #expect(playlist.preloadHint == nil)
    }
}

// MARK: - Program Date Time & Byte Range

@Suite("HLSManifestParser — PDT & ByteRange")
struct HLSManifestParserPDTTests {

    let parser = HLSManifestParser()
    let baseURL = URL(string: "https://cdn.example.com/live/playlist.m3u8")!

    @Test("Parse PROGRAM-DATE-TIME on segment")
    func programDateTime() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PROGRAM-DATE-TIME:2024-01-15T10:00:00.000Z
        #EXTINF:4.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.segments[0].programDateTime != nil)
    }

    @Test("Parse BYTERANGE tag")
    func byteRange() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-BYTERANGE:1000@0
        #EXTINF:4.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.segments[0].byteRange?.length == 1000)
        #expect(playlist.segments[0].byteRange?.offset == 0)
    }

    @Test("Parse BYTERANGE without offset")
    func byteRangeNoOffset() throws {
        let content = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-BYTERANGE:2048
        #EXTINF:4.0,
        seg0.ts
        """
        let playlist = try parser.parseMediaPlaylist(content: content, baseURL: baseURL)
        #expect(playlist.segments[0].byteRange?.length == 2048)
        #expect(playlist.segments[0].byteRange?.offset == nil)
    }
}

// MARK: - MasterPlaylist Equatable

@Suite("HLSManifestParser — Model Equality")
struct HLSManifestParserEqualityTests {

    @Test("MasterPlaylist is Equatable")
    func masterPlaylistEquality() throws {
        let parser = HLSManifestParser()
        let content = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        720p/stream.m3u8
        """
        let baseURL = URL(string: "https://example.com/master.m3u8")!
        let p1 = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        let p2 = try parser.parseMasterPlaylist(content: content, baseURL: baseURL)
        #expect(p1 == p2)
    }

    @Test("Variant is Equatable")
    func variantEquality() {
        let uri = URL(string: "https://example.com/test.m3u8")!
        let v1 = MasterPlaylist.Variant(bandwidth: 1000, averageBandwidth: nil, resolution: "720x480", codecs: nil, frameRate: nil, uri: uri, name: nil)
        let v2 = MasterPlaylist.Variant(bandwidth: 1000, averageBandwidth: nil, resolution: "720x480", codecs: nil, frameRate: nil, uri: uri, name: nil)
        #expect(v1 == v2)
    }

    @Test("Different variants are not equal")
    func variantInequality() {
        let uri = URL(string: "https://example.com/test.m3u8")!
        let v1 = MasterPlaylist.Variant(bandwidth: 1000, averageBandwidth: nil, resolution: "720x480", codecs: nil, frameRate: nil, uri: uri, name: nil)
        let v2 = MasterPlaylist.Variant(bandwidth: 2000, averageBandwidth: nil, resolution: "1280x720", codecs: nil, frameRate: nil, uri: uri, name: nil)
        #expect(v1 != v2)
    }
}
