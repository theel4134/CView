// MARK: - CViewCore/Utilities/Logging.swift
// 구조화된 로깅 시스템 — OSLog 기반

import Foundation
import os.log

/// 앱 로거 — OSLog 기반 구조화된 로깅
public enum AppLogger {
    // MARK: - Subsystems

    private static let subsystem = "com.cview.app"

    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let api = Logger(subsystem: subsystem, category: "API")
    public static let auth = Logger(subsystem: subsystem, category: "Auth")
    public static let chat = Logger(subsystem: subsystem, category: "Chat")
    public static let player = Logger(subsystem: subsystem, category: "Player")
    public static let hls = Logger(subsystem: subsystem, category: "HLS")
    public static let sync = Logger(subsystem: subsystem, category: "Sync")
    public static let gpu = Logger(subsystem: subsystem, category: "GPU")
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    public static let ui = Logger(subsystem: subsystem, category: "UI")
    public static let performance = Logger(subsystem: subsystem, category: "Performance")
    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let general = Logger(subsystem: subsystem, category: "General")
}

/// Backward compatibility alias
public typealias Log = AppLogger

// MARK: - Sensitive Data Masking Helpers

public enum LogMask {
    /// URL에서 query string을 제거하여 토큰/인증 파라미터 노출 방지
    /// - Example: "https://api.example.com/path?key=secret" → "https://api.example.com/path?[REDACTED]"
    public static func url(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "[invalid-url]"
        }
        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = nil
            return (components.string ?? url.host ?? "[url]") + "?[REDACTED]"
        }
        return components.string ?? url.host ?? "[url]"
    }

    /// URL 문자열에서 query string 제거
    public static func urlString(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "[invalid-url]" }
        return self.url(url)
    }

    /// 토큰/키의 앞부분만 노출 (기본 4자)
    /// - Example: "abcdef123456" → "abcd****"
    public static func token(_ value: String, prefixLength: Int = 4) -> String {
        guard value.count > prefixLength else { return "****" }
        return String(value.prefix(prefixLength)) + "****"
    }

    /// 응답 바디 등 민감할 수 있는 텍스트를 길이만 표시
    /// - Example: "{ \"token\": \"secret\" }" → "[body: 25 chars]"
    public static func body(_ text: String) -> String {
        "[body: \(text.count) chars]"
    }
}
