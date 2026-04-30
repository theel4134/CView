// MARK: - LiveInfoTests.swift
// CViewCore 라이브 정보 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - LiveInfo Tests

@Suite("LiveInfo")
struct LiveInfoTests {

    @Test("기본 memberwise init")
    func memberwiseInit() {
        let info = LiveInfo(liveId: 1, liveTitle: "테스트 방송")
        #expect(info.liveId == 1)
        #expect(info.liveTitle == "테스트 방송")
        #expect(info.status == .open)
        #expect(info.concurrentUserCount == 0)
        #expect(info.adult == false)
        #expect(info.tags.isEmpty)
        #expect(info.id == 1)
    }

    @Test("JSON 디코딩 — 기본 필드")
    func jsonDecodingBasic() throws {
        let json = """
        {
            "liveId": 42,
            "liveTitle": "방송 제목",
            "status": "OPEN",
            "concurrentUserCount": 1234,
            "adult": true,
            "tags": ["게임", "치지직"]
        }
        """
        let info = try JSONDecoder().decode(LiveInfo.self, from: Data(json.utf8))
        #expect(info.liveId == 42)
        #expect(info.liveTitle == "방송 제목")
        #expect(info.status == .open)
        #expect(info.concurrentUserCount == 1234)
        #expect(info.adult == true)
        #expect(info.tags == ["게임", "치지직"])
    }

    @Test("JSON 디코딩 — liveImageUrl {type} 플레이스홀더 치환")
    func liveImageURLPlaceholder() throws {
        let json = """
        {
            "liveId": 1,
            "liveTitle": "T",
            "status": "OPEN",
            "concurrentUserCount": 0,
            "liveImageUrl": "https://cdn.example.com/thumb/{type}/image.jpg"
        }
        """
        let info = try JSONDecoder().decode(LiveInfo.self, from: Data(json.utf8))
        #expect(info.liveImageURL?.absoluteString == "https://cdn.example.com/thumb/720/image.jpg")
        #expect(info.resolvedLiveImageURL == info.liveImageURL)
    }

    @Test("JSON 디코딩 — 필드 누락 시 기본값")
    func jsonDecodingDefaults() throws {
        let json = "{}"
        let info = try JSONDecoder().decode(LiveInfo.self, from: Data(json.utf8))
        #expect(info.liveId == 0)
        #expect(info.liveTitle == "")
        #expect(info.status == .open)
        #expect(info.concurrentUserCount == 0)
        #expect(info.adult == false)
        #expect(info.tags.isEmpty)
        #expect(info.liveImageURL == nil)
        #expect(info.chatChannelId == nil)
    }

    @Test("JSON 디코딩 — chatChannelId 포함")
    func jsonDecodingWithChat() throws {
        let json = """
        {
            "liveId": 5,
            "liveTitle": "T",
            "status": "CLOSE",
            "concurrentUserCount": 0,
            "chatChannelId": "chat_abc123"
        }
        """
        let info = try JSONDecoder().decode(LiveInfo.self, from: Data(json.utf8))
        #expect(info.status == .close)
        #expect(info.chatChannelId == "chat_abc123")
    }
}

// MARK: - LiveStatus Tests

@Suite("LiveStatus")
struct LiveStatusTests {

    @Test("rawValue 매핑")
    func rawValues() {
        #expect(LiveStatus.open.rawValue == "OPEN")
        #expect(LiveStatus.close.rawValue == "CLOSE")
    }

    @Test("JSON 디코딩")
    func decoding() throws {
        let data = Data("\"OPEN\"".utf8)
        let status = try JSONDecoder().decode(LiveStatus.self, from: data)
        #expect(status == .open)
    }
}

// MARK: - StreamQuality Tests

@Suite("StreamQuality")
struct StreamQualityTests {

    @Test("displayName 확인")
    func displayNames() {
        #expect(StreamQuality.auto.displayName == "자동")
        #expect(StreamQuality.source.displayName == "원본 (1080p)")
        #expect(StreamQuality.high.displayName == "고화질 (720p)")
        #expect(StreamQuality.medium.displayName == "중화질 (480p)")
        #expect(StreamQuality.low.displayName == "저화질 (360p)")
    }

    @Test("CaseIterable — 모든 케이스")
    func caseIterable() {
        #expect(StreamQuality.allCases.count == 5)
    }

    @Test("rawValue 매핑")
    func rawValues() {
        #expect(StreamQuality.auto.rawValue == "auto")
        #expect(StreamQuality.source.rawValue == "1080p")
    }
}

// MARK: - EncodingTrack Tests

@Suite("EncodingTrack")
struct EncodingTrackTests {

    @Test("JSON 디코딩 — videoFrameRate as Double")
    func frameRateDouble() throws {
        let json = """
        {
            "encodingTrackId": "track1",
            "videoFrameRate": 60.0,
            "videoWidth": 1920,
            "videoHeight": 1080
        }
        """
        let track = try JSONDecoder().decode(EncodingTrack.self, from: Data(json.utf8))
        #expect(track.encodingTrackId == "track1")
        #expect(track.videoFrameRate == 60.0)
        #expect(track.videoWidth == 1920)
        #expect(track.videoHeight == 1080)
    }

    @Test("JSON 디코딩 — videoFrameRate as String")
    func frameRateString() throws {
        let json = """
        {
            "encodingTrackId": "track2",
            "videoFrameRate": "30.0"
        }
        """
        let track = try JSONDecoder().decode(EncodingTrack.self, from: Data(json.utf8))
        #expect(track.videoFrameRate == 30.0)
    }

    @Test("JSON 디코딩 — videoFrameRate 누락")
    func frameRateMissing() throws {
        let json = """
        {"encodingTrackId": "track3"}
        """
        let track = try JSONDecoder().decode(EncodingTrack.self, from: Data(json.utf8))
        #expect(track.videoFrameRate == nil)
        #expect(track.encodingTrackId == "track3")
    }

    @Test("JSON 디코딩 — encodingTrackId 누락 시 빈 문자열")
    func missingTrackId() throws {
        let json = "{}"
        let track = try JSONDecoder().decode(EncodingTrack.self, from: Data(json.utf8))
        #expect(track.encodingTrackId == "")
    }

    @Test("JSON 디코딩 — 모든 옵셔널 필드")
    func fullDecoding() throws {
        let json = """
        {
            "encodingTrackId": "t1",
            "videoProfile": "high",
            "audioProfile": "aac",
            "videoCodec": "h264",
            "videoBitRate": 5000,
            "audioBitRate": 128,
            "videoFrameRate": 60.0,
            "videoWidth": 1920,
            "videoHeight": 1080,
            "audioChannel": 2
        }
        """
        let track = try JSONDecoder().decode(EncodingTrack.self, from: Data(json.utf8))
        #expect(track.videoProfile == "high")
        #expect(track.audioProfile == "aac")
        #expect(track.videoCodec == "h264")
        #expect(track.videoBitRate == 5000)
        #expect(track.audioBitRate == 128)
        #expect(track.audioChannel == 2)
    }
}

// MARK: - LivePlayback Tests

@Suite("LivePlayback")
struct LivePlaybackTests {

    @Test("기본 init")
    func defaultInit() {
        let playback = LivePlayback()
        #expect(playback.media.isEmpty)
        #expect(playback.live == nil)
    }

    @Test("JSON 라운드트립")
    func roundTrip() throws {
        let original = LivePlayback(
            media: [MediaInfo(mediaId: "m1", mediaProtocol: "HLS", path: "/live/stream.m3u8")],
            live: LivePlaybackDetail(start: "2024-01-01", status: "STARTED")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LivePlayback.self, from: data)
        #expect(decoded.media.count == 1)
        #expect(decoded.media[0].mediaId == "m1")
        #expect(decoded.live?.status == "STARTED")
    }
}

// MARK: - MediaInfo Tests

@Suite("MediaInfo")
struct MediaInfoTests {

    @Test("JSON 디코딩 — protocol 키 매핑")
    func protocolKeyMapping() throws {
        let json = """
        {
            "mediaId": "m1",
            "protocol": "HLS",
            "path": "/stream.m3u8"
        }
        """
        let media = try JSONDecoder().decode(MediaInfo.self, from: Data(json.utf8))
        #expect(media.mediaProtocol == "HLS")
        #expect(media.path == "/stream.m3u8")
    }
}

// MARK: - LivePlaybackDetail Tests

@Suite("LivePlaybackDetail")
struct LivePlaybackDetailTests {

    @Test("기본 init — 모두 nil")
    func defaultInit() {
        let detail = LivePlaybackDetail()
        #expect(detail.start == nil)
        #expect(detail.open == nil)
        #expect(detail.timeMachine == nil)
        #expect(detail.status == nil)
    }
}
