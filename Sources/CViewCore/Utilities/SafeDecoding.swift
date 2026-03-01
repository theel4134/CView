// MARK: - CViewCore/Utilities/SafeDecoding.swift
// 방어적 JSON 디코딩 유틸리티 — API 응답 필드 누락/타입 불일치 대응

import Foundation
import os.log

/// 방어적 JSON 디코딩 유틸리티
/// - API 응답에서 필드 누락, 타입 불일치 등을 안전하게 처리
public enum SafeDecoding {
    private static let logger = Logger(subsystem: "com.cview.app", category: "SafeDecoding")

    // MARK: - Default Fallback Decoding

    /// 키가 없거나 디코딩 실패 시 기본값 반환
    /// - Parameters:
    ///   - type: 디코딩할 타입
    ///   - container: KeyedDecodingContainer
    ///   - key: 디코딩할 키
    ///   - defaultValue: 실패 시 반환할 기본값
    /// - Returns: 디코딩된 값 또는 기본값
    public static func decode<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        default defaultValue: T
    ) -> T {
        do {
            return try container.decode(T.self, forKey: key)
        } catch {
            logger.warning("SafeDecoding: '\(key.stringValue)' 디코딩 실패, 기본값 사용 — \(error.localizedDescription, privacy: .public)")
            return defaultValue
        }
    }

    // MARK: - Optional Decoding (nil instead of throw)

    /// 키가 없거나 디코딩 실패 시 nil 반환 (throw 대신)
    /// - Parameters:
    ///   - type: 디코딩할 타입
    ///   - container: KeyedDecodingContainer
    ///   - key: 디코딩할 키
    /// - Returns: 디코딩된 값 또는 nil
    public static func decodeOptional<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> T? {
        do {
            return try container.decodeIfPresent(T.self, forKey: key)
        } catch {
            logger.warning("SafeDecoding: '\(key.stringValue)' optional 디코딩 실패, nil 반환 — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Flexible Type Decoding

    /// API가 문자열/숫자/불리언을 혼용하여 반환할 때 String으로 통합
    /// - Examples: `"hello"`, `123` → `"123"`, `true` → `"true"`, `3.14` → `"3.14"`
    public static func flexibleString<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> String? {
        // 1) 문자열 직접 디코딩
        if let str = try? container.decode(String.self, forKey: key) {
            return str
        }
        // 2) Int → String
        if let intVal = try? container.decode(Int.self, forKey: key) {
            logger.debug("SafeDecoding: '\(key.stringValue)' Int→String 변환")
            return String(intVal)
        }
        // 3) Double → String
        if let doubleVal = try? container.decode(Double.self, forKey: key) {
            logger.debug("SafeDecoding: '\(key.stringValue)' Double→String 변환")
            return String(doubleVal)
        }
        // 4) Bool → String
        if let boolVal = try? container.decode(Bool.self, forKey: key) {
            logger.debug("SafeDecoding: '\(key.stringValue)' Bool→String 변환")
            return String(boolVal)
        }
        return nil
    }

    /// API가 `"123"` 또는 `123` 형태로 정수를 반환할 때 Int로 통합
    public static func flexibleInt<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Int? {
        // 1) Int 직접 디코딩
        if let intVal = try? container.decode(Int.self, forKey: key) {
            return intVal
        }
        // 2) String → Int
        if let strVal = try? container.decode(String.self, forKey: key),
           let parsed = Int(strVal) {
            logger.debug("SafeDecoding: '\(key.stringValue)' String→Int 변환")
            return parsed
        }
        // 3) Double → Int (소수점 무시)
        if let doubleVal = try? container.decode(Double.self, forKey: key) {
            logger.debug("SafeDecoding: '\(key.stringValue)' Double→Int 변환")
            return Int(doubleVal)
        }
        return nil
    }

    // MARK: - Array Decoding (empty on failure)

    /// 배열 디코딩 실패 시 빈 배열 반환
    /// - 개별 요소 디코딩 실패도 건너뛰고 유효한 요소만 수집
    public static func decodeArray<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [T] {
        // 전체 배열 디코딩 시도
        if let array = try? container.decode([T].self, forKey: key) {
            return array
        }

        // 개별 요소별 실패 허용 디코딩
        guard var nestedContainer = try? container.nestedUnkeyedContainer(forKey: key) else {
            logger.warning("SafeDecoding: '\(key.stringValue)' 배열 컨테이너 없음, 빈 배열 반환")
            return []
        }

        var result: [T] = []
        var failCount = 0
        while !nestedContainer.isAtEnd {
            if let element = try? nestedContainer.decode(T.self) {
                result.append(element)
            } else {
                // 실패한 요소 건너뛰기: dummy decode로 커서 전진
                _ = try? nestedContainer.decode(AnyCodable.self)
                failCount += 1
            }
        }

        if failCount > 0 {
            logger.warning("SafeDecoding: '\(key.stringValue)' 배열 \(failCount)개 요소 디코딩 실패, \(result.count)개 성공")
        }

        return result
    }
}

// MARK: - AnyCodable (배열 내 실패 요소 스킵용)

/// 임의의 JSON 값을 디코딩하되 값 자체는 사용하지 않는 유틸리티 타입
private struct AnyCodable: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if let _ = try? container.decode(Bool.self) { return }
        if let _ = try? container.decode(Int.self) { return }
        if let _ = try? container.decode(Double.self) { return }
        if let _ = try? container.decode(String.self) { return }
        if let _ = try? container.decode([AnyCodable].self) { return }
        if let _ = try? container.decode([String: AnyCodable].self) { return }
        // 어떤 타입으로도 디코딩 불가 → 그냥 넘어감
    }
}
