// MARK: - CommonHeaders.swift
// 크로스 모듈 공통 HTTP 헤더 상수
// 7개+ 파일에서 중복 사용되던 User-Agent, Referer, Origin 문자열 통합

import Foundation

/// 치지직 API 통신에 사용되는 공통 HTTP 헤더 값
public enum CommonHeaders {
    /// Safari User-Agent (VLC, LocalStreamProxy, PDTLatencyProvider 등에서 사용)
    public static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Chrome User-Agent (ChzzkAPIClient, WebSocketService 등에서 사용)
    public static let chromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"

    /// Referer 헤더 값 (trailing slash 포함)
    public static let chzzkReferer = "https://chzzk.naver.com/"

    /// Origin 헤더 값 (trailing slash 없음)
    public static let chzzkOrigin = "https://chzzk.naver.com"
}
