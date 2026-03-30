// MARK: - KeychainServiceTests.swift
// CViewAuth — KeychainService 파일 기반 저장소 테스트

import Testing
import Foundation
@testable import CViewAuth

// MARK: - KeychainService (모든 테스트 직렬화 — 공유 디렉토리 사용)

@Suite("KeychainService", .serialized)
struct KeychainServiceTests {

    private static let prefix = UUID().uuidString
    private let svc = KeychainService()

    private func key(_ name: String) -> String { "\(Self.prefix)-\(name)" }

    // MARK: - CRUD

    @Test("데이터 저장 후 로드")
    func saveAndLoadData() async throws {
        let k = key("save-load")
        let data = Data("hello-keychain".utf8)
        try await svc.save(key: k, data: data)

        let loaded = try await svc.load(key: k)
        #expect(loaded == data)
        try await svc.delete(key: k)
    }

    @Test("존재하지 않는 키 로드 시 nil 반환")
    func loadMissingKey() async throws {
        let result = try await svc.load(key: key("nonexistent-\(UUID().uuidString)"))
        #expect(result == nil)
    }

    @Test("키 삭제 후 nil 반환")
    func deleteKey() async throws {
        let k = key("del-me")
        try await svc.save(key: k, data: Data("tmp".utf8))
        try await svc.delete(key: k)

        let loaded = try await svc.load(key: k)
        #expect(loaded == nil)
    }

    @Test("존재하지 않는 키 삭제 시 에러 없음")
    func deleteMissingKeyNoError() async throws {
        try await svc.delete(key: key("never-saved-\(UUID().uuidString)"))
    }

    @Test("같은 키에 덮어 쓰기")
    func overwriteKey() async throws {
        let k = key("ow")
        try await svc.save(key: k, data: Data("first".utf8))
        try await svc.save(key: k, data: Data("second".utf8))

        let loaded = try await svc.load(key: k)
        #expect(loaded == Data("second".utf8))
        try await svc.delete(key: k)
    }

    @Test("빈 데이터 저장 및 로드")
    func emptyData() async throws {
        let k = key("empty")
        try await svc.save(key: k, data: Data())

        let loaded = try await svc.load(key: k)
        #expect(loaded == Data())
        try await svc.delete(key: k)
    }

    @Test("큰 데이터 저장 및 로드")
    func largeData() async throws {
        let k = key("big")
        let large = Data(repeating: 0xAB, count: 1_000_000)
        try await svc.save(key: k, data: large)

        let loaded = try await svc.load(key: k)
        #expect(loaded == large)
        try await svc.delete(key: k)
    }

    // MARK: - String / Codable

    @Test("문자열 저장 및 로드")
    func saveAndLoadString() async throws {
        let k = key("str")
        try await svc.saveString(key: k, value: "안녕하세요 🌍")

        let loaded = try await svc.loadString(key: k)
        #expect(loaded == "안녕하세요 🌍")
        try await svc.delete(key: k)
    }

    @Test("빈 문자열 저장 및 로드")
    func emptyString() async throws {
        let k = key("es")
        try await svc.saveString(key: k, value: "")

        let loaded = try await svc.loadString(key: k)
        #expect(loaded == "")
        try await svc.delete(key: k)
    }

    @Test("존재하지 않는 문자열 키 로드 시 nil")
    func loadStringMissing() async throws {
        let result = try await svc.loadString(key: key("missing-\(UUID().uuidString)"))
        #expect(result == nil)
    }

    @Test("Codable 저장 및 로드")
    func saveCodableRoundTrip() async throws {
        struct Token: Codable, Sendable, Equatable {
            let access: String
            let expiresIn: Int
        }
        let k = key("token")
        let token = Token(access: "abc123", expiresIn: 3600)
        try await svc.saveCodable(key: k, value: token)

        let loaded = try await svc.loadCodable(key: k, as: Token.self)
        #expect(loaded == token)
        try await svc.delete(key: k)
    }

    @Test("존재하지 않는 Codable 키 로드 시 nil")
    func loadCodableMissing() async throws {
        struct Dummy: Codable, Sendable { let x: Int }
        let result = try await svc.loadCodable(key: key("nope-\(UUID().uuidString)"), as: Dummy.self)
        #expect(result == nil)
    }

    @Test("특수문자 키 안전하게 저장")
    func specialCharacterKey() async throws {
        let k = "\(Self.prefix)-com.cview/auth:token@2024"
        try await svc.saveString(key: k, value: "secret")

        let loaded = try await svc.loadString(key: k)
        #expect(loaded == "secret")
        try await svc.delete(key: k)
    }

    @Test("여러 키 동시 저장 후 독립적 조회")
    func multipleKeys() async throws {
        let k1 = key("mk1"), k2 = key("mk2"), k3 = key("mk3")
        try await svc.saveString(key: k1, value: "v1")
        try await svc.saveString(key: k2, value: "v2")
        try await svc.saveString(key: k3, value: "v3")

        #expect(try await svc.loadString(key: k1) == "v1")
        #expect(try await svc.loadString(key: k2) == "v2")
        #expect(try await svc.loadString(key: k3) == "v3")
        try await svc.delete(key: k1)
        try await svc.delete(key: k2)
        try await svc.delete(key: k3)
    }

    // MARK: - deleteAll (마지막에 실행 — 전체 클린업)

    @Test("deleteAll로 전체 삭제")
    func deleteAllKeys() async throws {
        let k1 = key("da1"), k2 = key("da2"), k3 = key("da3")
        try await svc.save(key: k1, data: Data("1".utf8))
        try await svc.save(key: k2, data: Data("2".utf8))
        try await svc.save(key: k3, data: Data("3".utf8))

        await svc.deleteAll()

        #expect(try await svc.load(key: k1) == nil)
        #expect(try await svc.load(key: k2) == nil)
        #expect(try await svc.load(key: k3) == nil)
    }
}
