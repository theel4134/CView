// MARK: - EmoticonModelsTests.swift
// CViewCore 이모티콘 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - EmoticonItem Tests

@Suite("EmoticonItem")
struct EmoticonItemTests {

    @Test("chatPattern 포맷 확인")
    func chatPattern() {
        let item = EmoticonItem(emoticonId: "d_54")
        #expect(item.chatPattern == "{:d_54:}")
    }

    @Test("id는 emoticonId")
    func identifiable() {
        let item = EmoticonItem(emoticonId: "abc123")
        #expect(item.id == "abc123")
    }

    @Test("JSON 디코딩 — imageUrl 키 매핑")
    func jsonDecoding() throws {
        let json = """
        {
            "emoticonId": "emo_1",
            "emoticonName": "하하",
            "imageUrl": "https://example.com/emo.png",
            "darkModeImageUrl": "https://example.com/emo_dark.png",
            "width": 48,
            "height": 48,
            "packId": "pack_1"
        }
        """
        let item = try JSONDecoder().decode(EmoticonItem.self, from: Data(json.utf8))
        #expect(item.emoticonId == "emo_1")
        #expect(item.emoticonName == "하하")
        #expect(item.imageURL?.absoluteString == "https://example.com/emo.png")
        #expect(item.darkModeImageURL?.absoluteString == "https://example.com/emo_dark.png")
        #expect(item.width == 48)
        #expect(item.height == 48)
        #expect(item.packId == "pack_1")
    }

    @Test("JSON 디코딩 — 옵셔널 필드 nil")
    func jsonDecodingMinimal() throws {
        let json = """
        {"emoticonId": "e1"}
        """
        let item = try JSONDecoder().decode(EmoticonItem.self, from: Data(json.utf8))
        #expect(item.emoticonId == "e1")
        #expect(item.emoticonName == nil)
        #expect(item.imageURL == nil)
    }
}

// MARK: - EmoticonPack Tests

@Suite("EmoticonPack")
struct EmoticonPackTests {

    @Test("id는 emoticonPackId")
    func identifiable() {
        let pack = EmoticonPack(emoticonPackId: "p1", emoticonPackName: "Pack")
        #expect(pack.id == "p1")
    }

    @Test("JSON 디코딩 — emoticonPackImageUrl 키 매핑")
    func jsonDecoding() throws {
        let json = """
        {
            "emoticonPackId": "p1",
            "emoticonPackName": "테스트팩",
            "emoticonPackImageUrl": "https://example.com/pack.png",
            "emoticonPackType": "SUBSCRIPTION",
            "emoticons": [{"emoticonId": "e1"}]
        }
        """
        let pack = try JSONDecoder().decode(EmoticonPack.self, from: Data(json.utf8))
        #expect(pack.emoticonPackId == "p1")
        #expect(pack.emoticonPackName == "테스트팩")
        #expect(pack.emoticonPackImageURL?.absoluteString == "https://example.com/pack.png")
        #expect(pack.emoticonPackType == "SUBSCRIPTION")
        #expect(pack.emoticons?.count == 1)
    }
}

// MARK: - EmoticonDeploy Tests

@Suite("EmoticonDeploy")
struct EmoticonDeployTests {

    @Test("allPacks — 일반 + 구독 합산")
    func allPacksMerge() {
        let deploy = EmoticonDeploy(
            emoticonPacks: [EmoticonPack(emoticonPackId: "p1", emoticonPackName: "A")],
            subscriptionEmoticonPacks: [EmoticonPack(emoticonPackId: "p2", emoticonPackName: "B")]
        )
        #expect(deploy.allPacks.count == 2)
        #expect(deploy.allPacks[0].emoticonPackId == "p1")
        #expect(deploy.allPacks[1].emoticonPackId == "p2")
    }

    @Test("allPacks — nil 처리")
    func allPacksNil() {
        let deploy = EmoticonDeploy()
        #expect(deploy.allPacks.isEmpty)
    }

    @Test("allEmoticons — 모든 팩 평탄화")
    func allEmoticons() {
        let deploy = EmoticonDeploy(
            emoticonPacks: [
                EmoticonPack(emoticonPackId: "p1", emoticonPackName: "A",
                             emoticons: [EmoticonItem(emoticonId: "e1"), EmoticonItem(emoticonId: "e2")])
            ],
            subscriptionEmoticonPacks: [
                EmoticonPack(emoticonPackId: "p2", emoticonPackName: "B",
                             emoticons: [EmoticonItem(emoticonId: "e3")])
            ]
        )
        #expect(deploy.allEmoticons.count == 3)
    }

    @Test("allEmoticons — emoticons nil인 팩은 빈 배열")
    func allEmoticonsEmptyPack() {
        let deploy = EmoticonDeploy(
            emoticonPacks: [EmoticonPack(emoticonPackId: "p1", emoticonPackName: "A")]
        )
        #expect(deploy.allEmoticons.isEmpty)
    }
}

// MARK: - ChatContentSegment Tests

@Suite("ChatContentSegment")
struct ChatContentSegmentTests {

    @Test("text id 형식")
    func textId() {
        let seg = ChatContentSegment.text("hello")
        #expect(seg.id.hasPrefix("text-"))
    }

    @Test("emoticon id 형식")
    func emoticonId() {
        let seg = ChatContentSegment.emoticon(id: "d_54", url: URL(string: "https://x.com/a.png")!)
        #expect(seg.id == "emo-d_54")
    }
}

// MARK: - EmoticonParser Tests

@Suite("EmoticonParser")
struct EmoticonParserTests {

    let parser = EmoticonParser()

    @Test("emojis가 nil이면 텍스트 1개 세그먼트")
    func nilEmojis() {
        let result = parser.parse(content: "안녕하세요", emojis: nil)
        #expect(result.count == 1)
        if case .text(let t) = result[0] { #expect(t == "안녕하세요") }
    }

    @Test("emojis가 비어있으면 텍스트 1개 세그먼트")
    func emptyEmojis() {
        let result = parser.parse(content: "hello", emojis: [:])
        #expect(result.count == 1)
    }

    @Test("Chzzk 형식 {:emoticonId:} 파싱")
    func chzzkFormat() {
        let emojis = ["d_54": "https://example.com/d_54.png"]
        let result = parser.parse(content: "{:d_54:}", emojis: emojis)
        #expect(result.count == 1)
        if case .emoticon(let id, let url) = result[0] {
            #expect(id == "d_54")
            #expect(url.absoluteString == "https://example.com/d_54.png")
        } else {
            Issue.record("이모티콘 세그먼트 기대")
        }
    }

    @Test("텍스트 + 이모티콘 혼합 파싱")
    func mixedContent() {
        let emojis = ["d_54": "https://example.com/d_54.png"]
        let result = parser.parse(content: "안녕 {:d_54:} 반가워", emojis: emojis)
        #expect(result.count == 3)
        if case .text(let t) = result[0] { #expect(t == "안녕 ") }
        if case .emoticon(let id, _) = result[1] { #expect(id == "d_54") }
        if case .text(let t) = result[2] { #expect(t == " 반가워") }
    }

    @Test("매칭 안되는 패턴은 원본 텍스트 유지")
    func unmatchedPattern() {
        let emojis = ["d_54": "https://example.com/d_54.png"]
        let result = parser.parse(content: "{:unknown:}", emojis: emojis)
        #expect(result.count == 1)
        if case .text(let t) = result[0] { #expect(t == "{:unknown:}") }
    }

    @Test("연속 이모티콘 파싱")
    func consecutiveEmoticons() {
        let emojis = [
            "a": "https://example.com/a.png",
            "b": "https://example.com/b.png",
        ]
        let result = parser.parse(content: "{:a:}{:b:}", emojis: emojis)
        #expect(result.count == 2)
        if case .emoticon(let id, _) = result[0] { #expect(id == "a") }
        if case .emoticon(let id, _) = result[1] { #expect(id == "b") }
    }

    @Test("빈 content")
    func emptyContent() {
        let result = parser.parse(content: "", emojis: ["d": "https://x.com"])
        // 빈 문자열은 패턴이 없으므로 텍스트 세그먼트 없이 반환될 수 있음
        #expect(result.isEmpty)
    }

    @Test("콜론 없는 이모티콘 ID도 매칭")
    func nocolonFormat() {
        let emojis = ["smile": "https://example.com/smile.png"]
        let result = parser.parse(content: "{smile}", emojis: emojis)
        #expect(result.count == 1)
        if case .emoticon(let id, _) = result[0] { #expect(id == "smile") }
    }

    @Test("rawId로 매칭되는 경우 (콜론 포함 키)")
    func rawIdMatch() {
        // emojis 딕셔너리가 rawId(콜론 포함)를 키로 사용하는 경우
        let emojis = [":special:": "https://example.com/special.png"]
        let result = parser.parse(content: "{:special:}", emojis: emojis)
        #expect(result.count == 1)
        if case .emoticon(let id, _) = result[0] { #expect(id == "special") }
    }
}
