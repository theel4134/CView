// MARK: - ChannelInfoTests.swift
// CViewCore 채널 정보 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - ChannelInfo Tests

@Suite("ChannelInfo")
struct ChannelInfoTests {

    @Test("기본 init")
    func memberwiseInit() {
        let ch = ChannelInfo(channelId: "ch1", channelName: "테스트 채널")
        #expect(ch.channelId == "ch1")
        #expect(ch.channelName == "테스트 채널")
        #expect(ch.channelImageURL == nil)
        #expect(ch.verifiedMark == false)
        #expect(ch.followerCount == 0)
        #expect(ch.channelDescription == nil)
        #expect(ch.id == "ch1")
    }

    @Test("JSON 디코딩 — 전체 필드")
    func jsonDecodingFull() throws {
        let json = """
        {
            "channelId": "abc",
            "channelName": "방송채널",
            "channelImageUrl": "https://example.com/img.png",
            "verifiedMark": true,
            "followerCount": 12345,
            "channelDescription": "소개글"
        }
        """
        let ch = try JSONDecoder().decode(ChannelInfo.self, from: Data(json.utf8))
        #expect(ch.channelId == "abc")
        #expect(ch.channelName == "방송채널")
        #expect(ch.channelImageURL?.absoluteString == "https://example.com/img.png")
        #expect(ch.verifiedMark == true)
        #expect(ch.followerCount == 12345)
        #expect(ch.channelDescription == "소개글")
    }

    @Test("JSON 디코딩 — 옵셔널 필드 누락 시 기본값")
    func jsonDecodingDefaults() throws {
        let json = """
        {
            "channelId": "ch2",
            "channelName": "최소"
        }
        """
        let ch = try JSONDecoder().decode(ChannelInfo.self, from: Data(json.utf8))
        #expect(ch.verifiedMark == false)
        #expect(ch.followerCount == 0)
        #expect(ch.channelImageURL == nil)
        #expect(ch.channelDescription == nil)
    }

    @Test("Hashable — 동일 채널 비교")
    func hashable() {
        let a = ChannelInfo(channelId: "ch1", channelName: "A")
        let b = ChannelInfo(channelId: "ch1", channelName: "A")
        #expect(a == b)
    }
}

// MARK: - FollowingChannel Tests

@Suite("FollowingChannel")
struct FollowingChannelTests {

    @Test("isLive — liveInfo 있으면 true")
    func isLiveTrue() {
        let ch = ChannelInfo(channelId: "ch1", channelName: "A")
        let live = LiveInfo(liveId: 1, liveTitle: "방송")
        let following = FollowingChannel(channel: ch, liveInfo: live)
        #expect(following.isLive == true)
        #expect(following.id == "ch1")
    }

    @Test("isLive — liveInfo 없으면 false")
    func isLiveFalse() {
        let ch = ChannelInfo(channelId: "ch2", channelName: "B")
        let following = FollowingChannel(channel: ch)
        #expect(following.isLive == false)
    }
}

// MARK: - StreamerInfo Tests

@Suite("StreamerInfo")
struct StreamerInfoTests {

    @Test("기본 init")
    func defaultInit() {
        let info = StreamerInfo()
        #expect(info.openLive == false)
    }

    @Test("openLive true")
    func openLiveTrue() {
        let info = StreamerInfo(openLive: true)
        #expect(info.openLive == true)
    }
}
