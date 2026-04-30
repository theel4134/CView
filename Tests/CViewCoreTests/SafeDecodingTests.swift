// MARK: - SafeDecodingTests.swift
// CViewCore — SafeDecoding 유틸리티 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - Test Helpers

/// 테스트용 Codable 구조체
private struct TestModel: Codable {
    enum CodingKeys: String, CodingKey {
        case name, age, score, tags, enabled
    }

    let name: String
    let age: Int
    let score: Double
    let tags: [String]
    let enabled: Bool

    init(name: String, age: Int, score: Double, tags: [String], enabled: Bool) {
        self.name = name
        self.age = age
        self.score = score
        self.tags = tags
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = SafeDecoding.decode(String.self, from: c, forKey: .name, default: "unknown")
        age = SafeDecoding.decode(Int.self, from: c, forKey: .age, default: 0)
        score = SafeDecoding.decode(Double.self, from: c, forKey: .score, default: 0.0)
        tags = SafeDecoding.decodeArray(String.self, from: c, forKey: .tags)
        enabled = SafeDecoding.decode(Bool.self, from: c, forKey: .enabled, default: false)
    }
}

private func decodeJSON<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(T.self, from: data)
}

// MARK: - Default Fallback Decoding

@Suite("SafeDecoding — Default Fallback")
struct SafeDecodingDefaultTests {

    @Test("Normal values decode correctly")
    func normalDecode() throws {
        let json = #"{"name":"홍길동","age":25,"score":95.5,"tags":["swift","ios"],"enabled":true}"#
        let model = try decodeJSON(json, as: TestModel.self)

        #expect(model.name == "홍길동")
        #expect(model.age == 25)
        #expect(model.score == 95.5)
        #expect(model.tags == ["swift", "ios"])
        #expect(model.enabled == true)
    }

    @Test("Missing key falls back to default")
    func missingKeyFallback() throws {
        let json = #"{}"#
        let model = try decodeJSON(json, as: TestModel.self)

        #expect(model.name == "unknown")
        #expect(model.age == 0)
        #expect(model.score == 0.0)
        #expect(model.tags.isEmpty)
        #expect(model.enabled == false)
    }

    @Test("Type mismatch falls back to default")
    func typeMismatch() throws {
        // age는 Int인데 "not-a-number" 문자열 → 기본값 0
        let json = #"{"name":"test","age":"not-a-number","score":"bad","tags":"not-array","enabled":"yes"}"#
        let model = try decodeJSON(json, as: TestModel.self)

        #expect(model.age == 0)
        #expect(model.score == 0.0)
        #expect(model.enabled == false)
    }
}

// MARK: - Optional Decoding

@Suite("SafeDecoding — Optional Decoding")
struct SafeDecodingOptionalTests {

    private struct OptModel: Decodable {
        enum CodingKeys: String, CodingKey { case value }
        let value: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = SafeDecoding.decodeOptional(String.self, from: c, forKey: .value)
        }
    }

    @Test("Present value decodes normally")
    func presentValue() throws {
        let json = #"{"value":"hello"}"#
        let model = try decodeJSON(json, as: OptModel.self)
        #expect(model.value == "hello")
    }

    @Test("Missing key returns nil")
    func missingKey() throws {
        let json = #"{}"#
        let model = try decodeJSON(json, as: OptModel.self)
        #expect(model.value == nil)
    }

    @Test("Null value returns nil")
    func nullValue() throws {
        let json = #"{"value":null}"#
        let model = try decodeJSON(json, as: OptModel.self)
        #expect(model.value == nil)
    }

    @Test("Type mismatch returns nil")
    func typeMismatch() throws {
        let json = #"{"value":12345}"#
        let model = try decodeJSON(json, as: OptModel.self)
        #expect(model.value == nil)
    }
}

// MARK: - Flexible String

@Suite("SafeDecoding — Flexible String")
struct SafeDecodingFlexibleStringTests {

    private struct FlexModel: Decodable {
        enum CodingKeys: String, CodingKey { case value }
        let value: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = SafeDecoding.flexibleString(from: c, forKey: .value)
        }
    }

    @Test("String value passes through")
    func stringValue() throws {
        let model = try decodeJSON(#"{"value":"hello"}"#, as: FlexModel.self)
        #expect(model.value == "hello")
    }

    @Test("Int converts to String")
    func intToString() throws {
        let model = try decodeJSON(#"{"value":42}"#, as: FlexModel.self)
        #expect(model.value == "42")
    }

    @Test("Double converts to String")
    func doubleToString() throws {
        let model = try decodeJSON(#"{"value":3.14}"#, as: FlexModel.self)
        #expect(model.value?.contains("3.14") == true)
    }

    @Test("Bool converts to String")
    func boolToString() throws {
        let model = try decodeJSON(#"{"value":true}"#, as: FlexModel.self)
        #expect(model.value == "true")
    }

    @Test("Missing key returns nil")
    func missingKey() throws {
        let model = try decodeJSON(#"{}"#, as: FlexModel.self)
        #expect(model.value == nil)
    }
}

// MARK: - Flexible Int

@Suite("SafeDecoding — Flexible Int")
struct SafeDecodingFlexibleIntTests {

    private struct FlexIntModel: Decodable {
        enum CodingKeys: String, CodingKey { case value }
        let value: Int?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = SafeDecoding.flexibleInt(from: c, forKey: .value)
        }
    }

    @Test("Int value passes through")
    func intValue() throws {
        let model = try decodeJSON(#"{"value":42}"#, as: FlexIntModel.self)
        #expect(model.value == 42)
    }

    @Test("String-encoded int converts")
    func stringToInt() throws {
        let model = try decodeJSON(#"{"value":"99"}"#, as: FlexIntModel.self)
        #expect(model.value == 99)
    }

    @Test("Double truncates to Int")
    func doubleToInt() throws {
        let model = try decodeJSON(#"{"value":7.9}"#, as: FlexIntModel.self)
        #expect(model.value == 7)
    }

    @Test("Non-numeric string returns nil")
    func nonNumericString() throws {
        let model = try decodeJSON(#"{"value":"abc"}"#, as: FlexIntModel.self)
        #expect(model.value == nil)
    }

    @Test("Missing key returns nil")
    func missingKey() throws {
        let model = try decodeJSON(#"{}"#, as: FlexIntModel.self)
        #expect(model.value == nil)
    }
}

// MARK: - Array Decoding

@Suite("SafeDecoding — Array Decoding")
struct SafeDecodingArrayTests {

    @Test("Normal array decodes correctly")
    func normalArray() throws {
        let json = #"{"name":"test","age":1,"score":0,"tags":["a","b","c"],"enabled":true}"#
        let model = try decodeJSON(json, as: TestModel.self)
        #expect(model.tags == ["a", "b", "c"])
    }

    @Test("Missing array key returns empty")
    func missingArray() throws {
        let json = #"{"name":"test","age":1,"score":0,"enabled":true}"#
        let model = try decodeJSON(json, as: TestModel.self)
        #expect(model.tags.isEmpty)
    }

    @Test("Null array returns empty")
    func nullArray() throws {
        let json = #"{"name":"test","age":1,"score":0,"tags":null,"enabled":true}"#
        let model = try decodeJSON(json, as: TestModel.self)
        #expect(model.tags.isEmpty)
    }
}

// MARK: - Double.safeForJSON

@Suite("SafeDecoding — Double.safeForJSON")
struct SafeForJSONTests {

    @Test("Finite value passes through")
    func finiteValue() {
        let value: Double = 42.5
        #expect(value.safeForJSON == 42.5)
    }

    @Test("NaN becomes 0")
    func nanToZero() {
        let value = Double.nan
        #expect(value.safeForJSON == 0)
    }

    @Test("Infinity becomes 0")
    func infinityToZero() {
        let value = Double.infinity
        #expect(value.safeForJSON == 0)
    }

    @Test("Negative infinity becomes 0")
    func negInfinityToZero() {
        let value = -Double.infinity
        #expect(value.safeForJSON == 0)
    }

    @Test("Optional finite passes through")
    func optionalFinite() {
        let value: Double? = 3.14
        #expect(value.safeForJSON == 3.14)
    }

    @Test("Optional NaN becomes nil")
    func optionalNaN() {
        let value: Double? = .nan
        #expect(value.safeForJSON == nil)
    }

    @Test("Optional nil stays nil")
    func optionalNil() {
        let value: Double? = nil
        #expect(value.safeForJSON == nil)
    }
}
