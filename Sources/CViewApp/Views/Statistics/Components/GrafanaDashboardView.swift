// MARK: - Statistics/Components/GrafanaDashboardView.swift
// 서버 분석 대시보드 (Grafana, https://cv.dododo.app/) 를 앱 내 임베드.
//
// 설계 결정 (2026-04-30):
// - 서버는 2026-04-29 부로 Superset → Grafana 로 전환됨 (server-dev/server.sh DEPRECATED 주석).
// - 서버 측 미러: server-dev/mirror/grafana/dashboards/{cview-overview, cview-system,
//   cview-app-player, cview-vlc-quality}.json
// - URL 패턴: https://cv.dododo.app/d/<uid>?kiosk=tv&theme=dark
//   - kiosk=tv  : Grafana chrome(사이드바·탑네브) 숨김 → 임베드 시 필수
//   - theme=dark: 다크모드 강제 (사용자 시스템 테마와 별개)
// - 익명 접근이 비활성화된 환경에서는 화면이 로그인 페이지로 리다이렉트되므로,
//   "외부 브라우저로 열기" 버튼을 항상 노출해 폴백 가능하게 한다.

import SwiftUI
import WebKit
import CViewCore
import CViewUI

/// Grafana 대시보드 식별자
enum GrafanaDashboard: String, CaseIterable, Identifiable {
    case overview   = "cview-overview"
    case system     = "cview-system"
    case appPlayer  = "cview-app-player"
    case vlcQuality = "cview-vlc-quality"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:   return "전체 개요"
        case .system:     return "시스템 메트릭"
        case .appPlayer:  return "앱 플레이어"
        case .vlcQuality: return "VLC 품질"
        }
    }

    var icon: String {
        switch self {
        case .overview:   return "chart.line.uptrend.xyaxis"
        case .system:     return "cpu"
        case .appPlayer:  return "play.rectangle.on.rectangle"
        case .vlcQuality: return "waveform.path.ecg"
        }
    }

    /// `https://cv.dododo.app/d/<uid>?kiosk=tv&theme=dark`
    func url(host: String = "https://cv.dododo.app") -> URL? {
        URL(string: "\(host)/d/\(rawValue)?kiosk=tv&theme=dark")
    }
}

/// Grafana 대시보드 임베드 (NSViewRepresentable / WKWebView).
struct GrafanaDashboardView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = CommonHeaders.chromeUserAgent
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // URL 변경 시에만 재로드
        if nsView.url?.absoluteString != url.absoluteString {
            nsView.load(URLRequest(url: url))
        }
    }
}
