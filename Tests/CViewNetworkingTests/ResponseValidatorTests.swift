// MARK: - ResponseValidatorTests.swift
// CViewNetworking — ResponseValidator JSON 구조 검증 테스트

import Testing
import Foundation
@testable import CViewNetworking
@testable import CViewCore

// MARK: - JSON Structure Validation

@Suite("ResponseValidator — JSON 구조 검증")
struct ResponseValidatorStructureTests {

    @Test("정상 응답 구조 검증 통과")
    func validStructure() {
        let json = """
        {"code": 200, "message": null, "content": {"name": "test"}}
        """
        let result = ResponseValidator.validateJSONStructure(Data(json.utf8))
        #expect(result.isValid)
        #expect(result.warnings.isEmpty)
    }

    @Test("code 누락 시 경고")
    func missingCode() {
        let json = """
        {"message": null, "content": {"name": "test"}}
        """
        let result = ResponseValidator.validateJSONStructure(Data(json.utf8))
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.contains("code") })
    }

    @Test("content 누락 시 경고")
    func missingContent() {
        let json = """
        {"code": 200, "message": null}
        """
        let result = ResponseValidator.validateJSONStructure(Data(json.utf8))
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.contains("content") })
    }

    @Test("code 비정상 값 경고")
    func errorCode() {
        let json = """
        {"code": 401, "message": "Unauthorized", "content": null}
        """
        let result = ResponseValidator.validateJSONStructure(Data(json.utf8))
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.contains("401") })
        #expect(result.warnings.contains { $0.contains("Unauthorized") })
    }

    @Test("유효하지 않은 JSON → invalid")
    func invalidJSON() {
        let result = ResponseValidator.validateJSONStructure(Data("not json".utf8))
        #expect(!result.isValid)
    }

    @Test("빈 JSON 객체 → invalid")
    func emptyJSONObject() {
        let result = ResponseValidator.validateJSONStructure(Data("{}".utf8))
        #expect(!result.isValid)
        #expect(result.warnings.contains { $0.contains("빈 JSON") })
    }

    @Test("JSON 배열은 object가 아니므로 invalid")
    func jsonArrayInvalid() {
        let result = ResponseValidator.validateJSONStructure(Data("[1, 2, 3]".utf8))
        #expect(!result.isValid)
    }
}

// MARK: - validateAndDecode

@Suite("ResponseValidator — validateAndDecode")
struct ResponseValidatorDecodeTests {

    private struct SimpleContent: Decodable, Sendable {
        let name: String
    }

    @Test("정상 디코딩")
    func successfulDecode() throws {
        let json = """
        {"code": 200, "content": {"name": "hello"}}
        """
        let result = try ResponseValidator.validateAndDecode(
            ChzzkResponse<SimpleContent>.self,
            from: Data(json.utf8),
            decoder: JSONDecoder()
        )
        #expect(result.code == 200)
        #expect(result.content?.name == "hello")
    }

    @Test("빈 데이터 → malformedResponse 에러")
    func emptyData() {
        #expect(throws: APIError.self) {
            try ResponseValidator.validateAndDecode(
                ChzzkResponse<SimpleContent>.self,
                from: Data(),
                decoder: JSONDecoder()
            )
        }
    }

    @Test("유효하지 않은 JSON → malformedResponse 에러")
    func invalidJSON() {
        #expect(throws: APIError.self) {
            try ResponseValidator.validateAndDecode(
                ChzzkResponse<SimpleContent>.self,
                from: Data("broken".utf8),
                decoder: JSONDecoder()
            )
        }
    }

    @Test("타입 불일치 → decodingFailed 에러")
    func typeMismatch() {
        let json = """
        {"code": "not-a-number", "content": {"name": 123}}
        """
        // ChzzkResponse.code 디코딩은 방어적이지만
        // content.name이 String 대신 Int이면 실패
        // ChzzkResponse의 방어적 디코딩으로 content가 nil이 됨 — 에러 안 남
        // 대신 직접 SimpleContent 디코딩을 시도
        #expect(throws: APIError.self) {
            try ResponseValidator.validateAndDecode(
                SimpleContent.self,
                from: Data(json.utf8),
                decoder: JSONDecoder()
            )
        }
    }
}

// MARK: - ChzzkResponse 디코딩

@Suite("ChzzkResponse — 방어적 디코딩")
struct ChzzkResponseDefensiveDecodingTests {

    private struct Item: Decodable, Sendable {
        let id: String
        let value: Int
    }

    @Test("정상 응답 디코딩")
    func normalResponse() throws {
        let json = """
        {"code": 200, "message": null, "content": {"id": "a1", "value": 42}}
        """
        let resp = try JSONDecoder().decode(ChzzkResponse<Item>.self, from: Data(json.utf8))
        #expect(resp.code == 200)
        #expect(resp.content?.id == "a1")
        #expect(resp.content?.value == 42)
    }

    @Test("code 누락 시 기본값 -1")
    func missingCode() throws {
        let json = """
        {"content": {"id": "b", "value": 1}}
        """
        let resp = try JSONDecoder().decode(ChzzkResponse<Item>.self, from: Data(json.utf8))
        #expect(resp.code == -1)
        #expect(resp.content?.id == "b")
    }

    @Test("content 디코딩 실패 시 nil")
    func contentDecodingFail() throws {
        let json = """
        {"code": 200, "content": {"id": 123, "value": "not-int"}}
        """
        let resp = try JSONDecoder().decode(ChzzkResponse<Item>.self, from: Data(json.utf8))
        #expect(resp.code == 200)
        #expect(resp.content == nil)
    }

    @Test("content 필드 누락 시 nil")
    func missingContent() throws {
        let json = """
        {"code": 200, "message": "ok"}
        """
        let resp = try JSONDecoder().decode(ChzzkResponse<Item>.self, from: Data(json.utf8))
        #expect(resp.content == nil)
    }

    @Test("message 포함 응답")
    func withMessage() throws {
        let json = """
        {"code": 401, "message": "Unauthorized", "content": null}
        """
        let resp = try JSONDecoder().decode(ChzzkResponse<Item>.self, from: Data(json.utf8))
        #expect(resp.code == 401)
        #expect(resp.message == "Unauthorized")
        #expect(resp.content == nil)
    }
}

// MARK: - PagedContent 디코딩

@Suite("PagedContent — 디코딩")
struct PagedContentDecodingTests {

    private struct SimpleItem: Decodable, Sendable {
        let name: String
    }

    @Test("정상 페이지 응답")
    func normalPaged() throws {
        let json = """
        {"size": 2, "totalCount": 100, "data": [{"name": "a"}, {"name": "b"}]}
        """
        let paged = try JSONDecoder().decode(PagedContent<SimpleItem>.self, from: Data(json.utf8))
        #expect(paged.size == 2)
        #expect(paged.totalCount == 100)
        #expect(paged.data.count == 2)
        #expect(paged.data[0].name == "a")
    }

    @Test("data 누락 시 빈 배열")
    func missingData() throws {
        let json = """
        {"size": 0}
        """
        let paged = try JSONDecoder().decode(PagedContent<SimpleItem>.self, from: Data(json.utf8))
        #expect(paged.data.isEmpty)
        #expect(paged.size == 0)
    }

    @Test("size 누락 시 0")
    func missingSize() throws {
        let json = """
        {"data": []}
        """
        let paged = try JSONDecoder().decode(PagedContent<SimpleItem>.self, from: Data(json.utf8))
        #expect(paged.size == 0)
    }

    @Test("page 정보 포함")
    func withPageInfo() throws {
        let json = """
        {"size": 1, "data": [{"name": "x"}], "page": {"next": {"concurrentUserCount": 500, "liveId": 10}}}
        """
        let paged = try JSONDecoder().decode(PagedContent<SimpleItem>.self, from: Data(json.utf8))
        #expect(paged.page?.next?.concurrentUserCount == 500)
        #expect(paged.page?.next?.liveId == 10)
    }
}

// MARK: - FollowingStreamer 로직

@Suite("FollowingStreamer — isActuallyLive")
struct FollowingStreamerTests {

    @Test("openLive true → 라이브")
    func openLiveTrue() {
        let s = FollowingStreamer(openLive: true)
        #expect(s.isActuallyLive)
    }

    @Test("openLive false → 오프라인")
    func openLiveFalse() {
        let s = FollowingStreamer(openLive: false)
        #expect(!s.isActuallyLive)
    }

    @Test("openLive nil → 라이브 간주")
    func openLiveNil() {
        let s = FollowingStreamer(openLive: nil)
        #expect(s.isActuallyLive)
    }

    @Test("liveStatus OPEN → 라이브 (openLive 무시)")
    func liveStatusOpen() {
        let s = FollowingStreamer(openLive: false, liveStatus: "OPEN")
        #expect(s.isActuallyLive)
    }

    @Test("liveStatus CLOSE → 오프라인")
    func liveStatusClose() {
        let s = FollowingStreamer(openLive: true, liveStatus: "CLOSE")
        #expect(!s.isActuallyLive)
    }
}

// MARK: - JSONDecoder.chzzk 날짜 파싱

@Suite("JSONDecoder.chzzk — 날짜 파싱")
struct ChzzkDateDecoderTests {

    private struct DateWrapper: Decodable {
        let date: Date
    }

    @Test("ISO 8601 소수초 포함")
    func iso8601WithFrac() throws {
        let json = """
        {"date": "2024-12-25T09:30:00.123Z"}
        """
        let decoded = try JSONDecoder.chzzk.decode(DateWrapper.self, from: Data(json.utf8))
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: decoded.date)
        #expect(components.year == 2024)
        #expect(components.month == 12)
        #expect(components.day == 25)
    }

    @Test("ISO 8601 소수초 없음")
    func iso8601NoFrac() throws {
        let json = """
        {"date": "2024-01-15T12:00:00Z"}
        """
        let decoded = try JSONDecoder.chzzk.decode(DateWrapper.self, from: Data(json.utf8))
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: decoded.date)
        #expect(components.year == 2024)
        #expect(components.hour == 12)
    }

    @Test("레거시 포맷 yyyy-MM-dd HH:mm:ss")
    func legacyFormat() throws {
        let json = """
        {"date": "2024-06-15 18:30:00"}
        """
        let decoded = try JSONDecoder.chzzk.decode(DateWrapper.self, from: Data(json.utf8))
        #expect(decoded.date != Date.distantPast) // Successfully parsed
    }

    @Test("인식 불가 포맷 → 에러")
    func unknownFormat() {
        let json = """
        {"date": "not-a-date"}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder.chzzk.decode(DateWrapper.self, from: Data(json.utf8))
        }
    }
}

// MARK: - NetworkConstants

@Suite("NetworkConstants")
struct NetworkConstantsValueTests {

    @Test("APIDefaults 상수 유효성")
    func apiDefaults() {
        #expect(APIDefaults.requestTimeout > 0)
        #expect(APIDefaults.resourceTimeout > APIDefaults.requestTimeout)
        #expect(APIDefaults.cachePurgeInterval > 0)
        #expect(APIDefaults.allLivesMaxPages > 0)
    }

    @Test("ImageCacheDefaults 상수 유효성")
    func imageCacheDefaults() {
        #expect(ImageCacheDefaults.diskCacheMaxSize > 0)
        #expect(ImageCacheDefaults.memoryCacheCountLimit > 0)
        #expect(ImageCacheDefaults.decodedCacheCountLimit > 0)
    }

    @Test("ResponseCacheDefaults 상수")
    func responseCacheDefaults() {
        #expect(ResponseCacheDefaults.maxEntries == 100)
        #expect(ResponseCacheDefaults.defaultTTL == 300)
    }

    @Test("MetricsNetDefaults 상수")
    func metricsDefaults() {
        #expect(MetricsNetDefaults.maxReconnectAttempts > 0)
        #expect(MetricsNetDefaults.maxBackoffDelay > 0)
    }
}

// MARK: - UserStatusInfo 디코딩

@Suite("UserStatusInfo — 디코딩")
struct UserStatusInfoDecodingTests {

    @Test("정상 디코딩")
    func normalDecode() throws {
        let json = """
        {
            "hasProfile": true,
            "userIdHash": "hash123",
            "nickname": "테스터",
            "profileImageUrl": "https://example.com/img.png",
            "penalties": [],
            "loggedIn": true
        }
        """
        let info = try JSONDecoder().decode(UserStatusInfo.self, from: Data(json.utf8))
        #expect(info.hasProfile == true)
        #expect(info.userIdHash == "hash123")
        #expect(info.nickname == "테스터")
        #expect(info.loggedIn == true)
    }

    @Test("모든 필드 null")
    func allNull() throws {
        let json = """
        {
            "hasProfile": null,
            "userIdHash": null,
            "nickname": null,
            "profileImageUrl": null,
            "penalties": null,
            "loggedIn": null
        }
        """
        let info = try JSONDecoder().decode(UserStatusInfo.self, from: Data(json.utf8))
        #expect(info.hasProfile == nil)
        #expect(info.loggedIn == nil)
    }
}
