// MARK: - SearchModelsTests.swift
// CViewCore 검색 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - SearchType Tests

@Suite("SearchType")
struct SearchTypeTests {

    @Test("rawValue 매핑")
    func rawValues() {
        #expect(SearchType.channel.rawValue == "channel")
        #expect(SearchType.live.rawValue == "live")
        #expect(SearchType.video.rawValue == "video")
        #expect(SearchType.clip.rawValue == "clip")
    }

    @Test("CaseIterable")
    func caseIterable() {
        #expect(SearchType.allCases.count == 4)
    }
}

// MARK: - SearchResult Tests

@Suite("SearchResult")
struct SearchResultTests {

    @Test("기본 init")
    func defaultInit() {
        let result = SearchResult<ChannelSearchItem>()
        #expect(result.size == 0)
        #expect(result.page == nil)
        #expect(result.totalCount == nil)
        #expect(result.data.isEmpty)
    }

    @Test("JSON 디코딩 — 정상 응답")
    func jsonDecoding() throws {
        let json = """
        {
            "size": 2,
            "totalCount": 100,
            "data": [
                {"channel": {"channelId": "ch1", "channelName": "채널1"}, "openLive": true},
                {"channel": {"channelId": "ch2", "channelName": "채널2"}}
            ]
        }
        """
        let result = try JSONDecoder().decode(SearchResult<ChannelSearchItem>.self, from: Data(json.utf8))
        #expect(result.size == 2)
        #expect(result.totalCount == 100)
        #expect(result.data.count == 2)
        #expect(result.data[0].channel.channelId == "ch1")
        #expect(result.data[0].openLive == true)
    }

    @Test("JSON 디코딩 — page가 Object")
    func pageAsObject() throws {
        let json = """
        {
            "size": 1,
            "page": {"next": {"offset": 20}},
            "data": []
        }
        """
        let result = try JSONDecoder().decode(SearchResult<ChannelSearchItem>.self, from: Data(json.utf8))
        #expect(result.page?.next?.offset == 20)
    }

    @Test("JSON 디코딩 — page가 null")
    func pageAsNull() throws {
        let json = """
        {
            "size": 0,
            "page": null,
            "data": []
        }
        """
        let result = try JSONDecoder().decode(SearchResult<ChannelSearchItem>.self, from: Data(json.utf8))
        #expect(result.page == nil)
    }

    @Test("JSON 디코딩 — 필드 누락 시 기본값")
    func missingFields() throws {
        let json = "{}"
        let result = try JSONDecoder().decode(SearchResult<ChannelSearchItem>.self, from: Data(json.utf8))
        #expect(result.size == 0)
        #expect(result.data.isEmpty)
        #expect(result.totalCount == nil)
    }
}

// MARK: - VODInfo Tests

@Suite("VODInfo")
struct VODInfoTests {

    @Test("formattedDuration — 시/분/초 포맷")
    func formattedDurationHours() {
        let vod = VODInfo(videoNo: 1, videoTitle: "T", duration: 3661) // 1:01:01
        #expect(vod.formattedDuration == "1:01:01")
    }

    @Test("formattedDuration — 분/초 포맷")
    func formattedDurationMinutes() {
        let vod = VODInfo(videoNo: 1, videoTitle: "T", duration: 125) // 2:05
        #expect(vod.formattedDuration == "2:05")
    }

    @Test("formattedDuration — 0초")
    func formattedDurationZero() {
        let vod = VODInfo(videoNo: 1, videoTitle: "T", duration: 0)
        #expect(vod.formattedDuration == "0:00")
    }

    @Test("formattedDuration — 정확히 1시간")
    func formattedDurationExactHour() {
        let vod = VODInfo(videoNo: 1, videoTitle: "T", duration: 3600)
        #expect(vod.formattedDuration == "1:00:00")
    }

    @Test("id는 videoNo")
    func identifiable() {
        let vod = VODInfo(videoNo: 42, videoTitle: "T")
        #expect(vod.id == 42)
    }

    @Test("JSON 디코딩 — videoImageUrl 키 매핑")
    func jsonDecoding() throws {
        let json = """
        {
            "videoNo": 1,
            "videoTitle": "영상",
            "videoImageUrl": "https://example.com/thumb.jpg",
            "duration": 120,
            "readCount": 5000
        }
        """
        let vod = try JSONDecoder().decode(VODInfo.self, from: Data(json.utf8))
        #expect(vod.videoNo == 1)
        #expect(vod.videoTitle == "영상")
        #expect(vod.videoImageURL?.absoluteString == "https://example.com/thumb.jpg")
        #expect(vod.duration == 120)
        #expect(vod.readCount == 5000)
    }
}

// MARK: - ClipInfo Tests

@Suite("ClipInfo")
struct ClipInfoTests {

    @Test("id는 clipUID")
    func identifiable() {
        let clip = ClipInfo(clipUID: "uid123", clipTitle: "클립")
        #expect(clip.id == "uid123")
    }

    @Test("JSON 디코딩 — clipUID (대문자, list API)")
    func jsonDecodingClipUID() throws {
        let json = """
        {
            "clipUID": "clip_001",
            "clipTitle": "멋진 클립",
            "duration": 30,
            "readCount": 100,
            "ownerChannel": {"channelId": "ch1", "channelName": "채널1"}
        }
        """
        let clip = try JSONDecoder().decode(ClipInfo.self, from: Data(json.utf8))
        #expect(clip.clipUID == "clip_001")
        #expect(clip.clipTitle == "멋진 클립")
        #expect(clip.channel?.channelId == "ch1")
    }

    @Test("JSON 디코딩 — clipUid (소문자, detail API)")
    func jsonDecodingClipUid() throws {
        let json = """
        {
            "clipUid": "clip_002",
            "clipTitle": "디테일 클립",
            "duration": 15,
            "readCount": 50,
            "channel": {"channelId": "ch2", "channelName": "채널2"}
        }
        """
        let clip = try JSONDecoder().decode(ClipInfo.self, from: Data(json.utf8))
        #expect(clip.clipUID == "clip_002")
        #expect(clip.channel?.channelId == "ch2")
    }

    @Test("JSON 디코딩 — clipUID/clipUid 둘 다 없으면 빈 문자열")
    func jsonDecodingNoUID() throws {
        let json = """
        {"clipTitle": "무ID"}
        """
        let clip = try JSONDecoder().decode(ClipInfo.self, from: Data(json.utf8))
        #expect(clip.clipUID == "")
        #expect(clip.clipTitle == "무ID")
    }

    @Test("JSON 디코딩 — 빈 clipUID면 clipUid로 폴백")
    func jsonDecodingEmptyClipUID() throws {
        let json = """
        {
            "clipUID": "",
            "clipUid": "fallback_uid",
            "clipTitle": "폴백"
        }
        """
        let clip = try JSONDecoder().decode(ClipInfo.self, from: Data(json.utf8))
        #expect(clip.clipUID == "fallback_uid")
    }

    @Test("JSON 인코딩/디코딩 라운드트립")
    func roundTrip() throws {
        let original = ClipInfo(
            clipUID: "uid1", clipTitle: "Title",
            clipURL: URL(string: "https://example.com/clip"),
            duration: 60, readCount: 200
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipInfo.self, from: data)
        #expect(decoded.clipUID == "uid1")
        #expect(decoded.clipTitle == "Title")
        #expect(decoded.duration == 60)
    }

    @Test("JSON 디코딩 — thumbnailImageUrl/clipUrl 키 매핑")
    func urlKeyMapping() throws {
        let json = """
        {
            "clipUID": "c1",
            "clipTitle": "T",
            "thumbnailImageUrl": "https://example.com/thumb.jpg",
            "clipUrl": "https://example.com/clip.mp4"
        }
        """
        let clip = try JSONDecoder().decode(ClipInfo.self, from: Data(json.utf8))
        #expect(clip.thumbnailImageURL?.absoluteString == "https://example.com/thumb.jpg")
        #expect(clip.clipURL?.absoluteString == "https://example.com/clip.mp4")
    }
}

// MARK: - AutocompleteSuggestion Tests

@Suite("AutocompleteSuggestion")
struct AutocompleteSuggestionTests {

    @Test("생성 및 프로퍼티")
    func initAndProperties() {
        let s = AutocompleteSuggestion(text: "검색어", kind: .recent)
        #expect(s.text == "검색어")
        #expect(s.kind == .recent)
    }

    @Test("following kind")
    func followingKind() {
        let s = AutocompleteSuggestion(text: "채널명", kind: .following)
        #expect(s.kind == .following)
    }
}

// MARK: - LiveSortOption Tests

@Suite("LiveSortOption")
struct LiveSortOptionTests {

    @Test("rawValue 매핑")
    func rawValues() {
        #expect(LiveSortOption.viewerCount.rawValue == "시청자 많은순")
        #expect(LiveSortOption.recent.rawValue == "최신순")
    }

    @Test("CaseIterable")
    func caseIterable() {
        #expect(LiveSortOption.allCases.count == 2)
    }
}
