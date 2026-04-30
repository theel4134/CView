// MARK: - CViewNetworking/ResponseValidator.swift
// API 응답 구조 검증기 — JSON 무결성 확인 및 방어적 디코딩

import Foundation
import os.log
import CViewCore

/// API 응답 구조 검증기
/// - JSON 응답의 구조적 유효성을 사전 검증하여 디코딩 실패를 사전 방지
/// - 경고 로그를 통해 API 변경 사항 조기 탐지
public enum ResponseValidator {
    private static let logger = Logger(subsystem: "com.cview.app", category: "ResponseValidator")

    // MARK: - Validation Result

    /// 구조 검증 결과
    public struct ValidationResult: Sendable {
        public let isValid: Bool
        public let warnings: [String]

        public init(isValid: Bool, warnings: [String] = []) {
            self.isValid = isValid
            self.warnings = warnings
        }
    }

    // MARK: - Validate and Decode

    /// API 응답 데이터를 검증 후 디코딩
    /// - Parameters:
    ///   - type: 디코딩 대상 타입
    ///   - data: 원시 응답 데이터
    ///   - decoder: JSONDecoder 인스턴스
    /// - Returns: 디코딩된 객체
    /// - Throws: `APIError.decodingFailed` 또는 `APIError.malformedResponse`
    public static func validateAndDecode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder
    ) throws -> T {
        // 1) 빈 데이터 검사
        guard !data.isEmpty else {
            logger.error("ResponseValidator: 빈 응답 데이터")
            throw APIError.malformedResponse("응답 데이터가 비어있습니다")
        }

        // 2) JSON 구조 검증
        let validation = validateJSONStructure(data)
        if !validation.warnings.isEmpty {
            for warning in validation.warnings {
                logger.warning("ResponseValidator: \(warning, privacy: .public)")
            }
        }

        if !validation.isValid {
            let detail = validation.warnings.joined(separator: "; ")
            logger.error("ResponseValidator: 심각한 구조 오류 — \(detail, privacy: .public)")
            throw APIError.malformedResponse(detail)
        }

        // 3) 디코딩 시도
        do {
            let decoded = try decoder.decode(type, from: data)
            return decoded
        } catch let decodingError as DecodingError {
            let detail = Self.describeDecodingError(decodingError)
            logger.error("ResponseValidator: 디코딩 실패 — \(detail, privacy: .public)")

            // 디버그: 원시 데이터 일부 로깅 (최대 500자)
            if let rawStr = String(data: data.prefix(500), encoding: .utf8) {
                logger.debug("ResponseValidator: raw(500자 제한) = \(rawStr, privacy: .private)")
            }

            throw APIError.decodingFailed(detail)
        } catch {
            logger.error("ResponseValidator: 알 수 없는 디코딩 오류 — \(error.localizedDescription, privacy: .public)")
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - JSON Structure Validation

    /// JSON 데이터의 구조적 유효성 검증
    /// - 치지직 API 표준 응답 (`code`, `message`, `content`) 구조 확인
    /// - Parameter data: 원시 JSON 데이터
    /// - Returns: 검증 결과 (유효성 + 경고 목록)
    public static func validateJSONStructure(_ data: Data) -> ValidationResult {
        var warnings: [String] = []

        // JSON 파싱
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ValidationResult(isValid: false, warnings: ["유효한 JSON 객체가 아닙니다"])
        }

        // code 필드 검사
        if json["code"] == nil {
            warnings.append("'code' 필드 누락")
        } else if let code = json["code"] as? Int, code != 200 {
            warnings.append("API 응답 code=\(code) (비정상)")
        }

        // content 필드 검사
        if json["content"] == nil {
            // content가 null인 경우는 emptyContent로 처리될 수 있으므로 warning만
            warnings.append("'content' 필드가 null 또는 누락")
        }

        // message 필드 검사 (정보성)
        if let message = json["message"] as? String, !message.isEmpty {
            // 에러 메시지가 있으면 경고
            if json["code"] as? Int != 200 {
                warnings.append("API 메시지: \(message)")
            }
        }

        // 심각한 구조 오류: JSON이지만 빈 객체
        if json.isEmpty {
            return ValidationResult(isValid: false, warnings: ["빈 JSON 객체"])
        }

        return ValidationResult(isValid: true, warnings: warnings)
    }

    // MARK: - DecodingError Description Helper

    /// DecodingError를 사람이 읽기 쉬운 문자열로 변환
    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "타입 불일치: \(type) at '\(path)' — \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "값 없음: \(type) at '\(path)' — \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "키 없음: '\(key.stringValue)' at '\(path)' — \(context.debugDescription)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "데이터 손상 at '\(path)' — \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
