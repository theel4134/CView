// MARK: - HLSJSVideoView.swift
// CViewPlayer — hls.js 비디오 렌더링을 위한 WKWebView 호스트 뷰
//
// [설계]
// • WKWebView 내부에서 hls.js + <video> 로 HLS 스트림 재생
// • JS→Swift: WKScriptMessageHandler ('player' 핸들러)
// • Swift→JS: evaluateJavaScript() 래퍼 메서드
// • 메트릭 수집은 JS 측에서 2초 주기로 postMessage

import Foundation
import AppKit
import WebKit
import CViewCore

// MARK: - JS→Swift 메시지 타입

/// JS에서 Swift로 전달되는 메시지 타입
enum HLSJSMessageType: String {
    case ready
    case metrics
    case manifestParsed
    case levelSwitched
    case error
    case fatalError
    case fragLoaded
    case playStarted
}

// MARK: - HLS.js 이벤트

/// HLS.js 이벤트 (Swift 측 처리용)
public enum HLSJSEvent: Sendable {
    case manifestParsed(levels: Int, audioTracks: Int)
    case levelSwitched(level: Int, width: Int, height: Int, bitrate: Int)
    case error(fatal: Bool, type: String, details: String)
    case fatalError(type: String, details: String)
    case fragLoaded(duration: Double, sn: Int, level: Int, loadTime: Double)
}

// MARK: - HLSJSVideoView

/// hls.js 기반 비디오 플레이어 뷰 — WKWebView 호스팅
public final class HLSJSVideoView: NSView, @unchecked Sendable {

    // MARK: - Properties

    private var webView: WKWebView!
    private var isPageLoaded = false
    private var pendingSource: (url: String, profile: String)?
    private var pendingVolume: Float = 1.0
    private var pendingMuted: Bool = false

    /// 메트릭 콜백 (2초 주기)
    public var onMetrics: (@Sendable (HLSJSLiveMetrics) -> Void)?

    /// 이벤트 콜백
    public var onEvent: (@Sendable (HLSJSEvent) -> Void)?

    /// 상태 변경 콜백
    public var onStateChange: (@Sendable (PlayerState.Phase) -> Void)?

    /// hls.js 준비 완료 콜백
    public var onReady: (() -> Void)?

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupWebView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // 인라인 미디어 재생 허용
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = false

        // JS→Swift 메시지 핸들러
        let handler = HLSJSMessageHandler(view: self)
        config.userContentController.add(handler, name: "player")

        webView = WKWebView(frame: bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]

        // 투명 배경 (비디오 아래 검정색은 HTML에서 처리)
        webView.setValue(false, forKey: "drawsBackground")

        // 네비게이션 비활성화 (보안)
        webView.allowsBackForwardNavigationGestures = false

        addSubview(webView)
        loadPlayerPage()
    }

    private func loadPlayerPage() {
        // hls.js 라이브러리를 HTML에 인라인하여 loadHTMLString으로 로드
        // file:// 출처 대신 about:blank 파생 출처 사용 → 자동재생 정책 완화
        guard let htmlURL = Bundle.module.url(forResource: "hlsjs-player", withExtension: "html")
                ?? Bundle.module.url(forResource: "hlsjs-player", withExtension: "html", subdirectory: "Resources"),
              let jsURL = Bundle.module.url(forResource: "hls.min", withExtension: "js")
                ?? Bundle.module.url(forResource: "hls.min", withExtension: "js", subdirectory: "Resources")
        else {
            AppLogger.player.error("HLSJSVideoView: HTML/JS 리소스를 찾을 수 없음")
            onStateChange?(.error(.engineInitFailed))
            return
        }

        do {
            var htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
            let jsContent = try String(contentsOf: jsURL, encoding: .utf8)
            // <script src="hls.min.js"></script> → <script>{인라인 코드}</script>
            htmlContent = htmlContent.replacingOccurrences(
                of: "<script src=\"hls.min.js\"></script>",
                with: "<script>\(jsContent)</script>"
            )
            AppLogger.player.debug("HLSJSVideoView: loadHTMLString (inline hls.js, \(jsContent.count) chars)")
            webView.loadHTMLString(htmlContent, baseURL: URL(string: "http://localhost"))
        } catch {
            AppLogger.player.error("HLSJSVideoView: 리소스 읽기 실패 — \(error.localizedDescription, privacy: .public)")
            onStateChange?(.error(.engineInitFailed))
        }
    }

    // MARK: - Swift→JS API

    /// HLS 소스 로드
    public func loadSource(url: String, profile: String = "lowLatency") {
        guard isPageLoaded else {
            AppLogger.player.debug("HLSJSVideoView: 페이지 미로드 → pendingSource 저장")
            pendingSource = (url, profile)
            return
        }
        let escaped = url.replacingOccurrences(of: "'", with: "\\'")
            AppLogger.player.debug("HLSJSVideoView: loadSource (profile=\(profile, privacy: .public))")
        evaluateJS("loadSource('\(escaped)', '\(profile)')")
    }

    /// 재생
    public func play() { evaluateJS("play()") }

    /// 일시정지
    public func pause() { evaluateJS("pause()") }

    /// 정지
    public func stopPlayback() { evaluateJS("stop()") }

    /// 라이브 엣지로 이동
    public func seekToLiveEdge() { evaluateJS("seekToLiveEdge()") }

    /// 볼륨 설정 (0.0~1.0)
    public func setVolume(_ volume: Float) {
        pendingVolume = volume
        if isPageLoaded { evaluateJS("setVolume(\(volume))") }
    }

    /// 음소거
    public func setMuted(_ muted: Bool) {
        pendingMuted = muted
        if isPageLoaded { evaluateJS("setMuted(\(muted))") }
    }

    /// 재생 속도
    public func setRate(_ rate: Float) {
        evaluateJS("setRate(\(rate))")
    }

    /// 시크
    public func seek(to time: TimeInterval) {
        evaluateJS("seek(\(time))")
    }

    /// 최대 비트레이트 캡 (kbps)
    public func setMaxBitrate(_ maxKbps: Int) {
        evaluateJS("setMaxBitrate(\(maxKbps))")
    }

    /// 최대 해상도 캡 (height 기준)
    public func setMaxResolution(_ maxHeight: Int) {
        evaluateJS("setMaxResolution(\(maxHeight))")
    }

    /// hls.js 인스턴스 파괴
    public func destroyHls() {
        evaluateJS("destroyHls()")
        isPageLoaded = false
    }

    /// 풀 반납 전 리셋
    public func resetForReuse() {
        evaluateJS("destroyHls()")
        onMetrics = nil
        onEvent = nil
        onStateChange = nil
        onReady = nil
        pendingSource = nil
        pendingVolume = 1.0
        pendingMuted = false
    }

    // MARK: - Private

    private func evaluateJS(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                AppLogger.player.debug("HLSJSVideoView JS error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - JS→Swift 메시지 처리

    fileprivate func handleMessage(_ message: [String: Any]) {
        guard let typeStr = message["type"] as? String,
              let type = HLSJSMessageType(rawValue: typeStr) else { return }

        let data = message["data"] as? [String: Any] ?? [:]

        switch type {
        case .ready:
            isPageLoaded = true
            let hlsSupported = (data["hlsSupported"] as? Bool) ?? false
            let hasPending = self.pendingSource != nil
            AppLogger.player.debug("HLSJSVideoView: ready (hlsSupported=\(hlsSupported), hasPending=\(hasPending))")
            onReady?()
            // 페이지 로드 전에 설정된 볼륨/음소거 적용
            evaluateJS("setVolume(\(pendingVolume))")
            evaluateJS("setMuted(\(pendingMuted))")
            // 페이지 로드 전에 요청된 소스가 있으면 로드
            if let pending = pendingSource {
                pendingSource = nil
                loadSource(url: pending.url, profile: pending.profile)
            }

        case .metrics:
            let metrics = parseMetrics(data)
            onMetrics?(metrics)

        case .manifestParsed:
            AppLogger.player.debug("HLSJSVideoView: manifestParsed (levels=\(data["levels"] as? Int ?? 0))")
            let levels = data["levels"] as? Int ?? 0
            let audio = data["audioTracks"] as? Int ?? 0
            onEvent?(.manifestParsed(levels: levels, audioTracks: audio))
            onStateChange?(.playing)

        case .levelSwitched:
            let level = data["level"] as? Int ?? 0
            let width = data["width"] as? Int ?? 0
            let height = data["height"] as? Int ?? 0
            let bitrate = data["bitrate"] as? Int ?? 0
            onEvent?(.levelSwitched(level: level, width: width, height: height, bitrate: bitrate))

        case .error:
            let fatal = data["fatal"] as? Bool ?? false
            let errType = data["type"] as? String ?? "unknown"
            let details = data["details"] as? String ?? ""
            AppLogger.player.debug("HLSJSVideoView: error (fatal=\(fatal), type=\(errType, privacy: .public), details=\(details, privacy: .public))")
            onEvent?(.error(fatal: fatal, type: errType, details: details))
            if fatal {
                onStateChange?(.error(.hlsParsingFailed("\(errType): \(details)")))
            }

        case .fatalError:
            let errType = data["type"] as? String ?? "unknown"
            let details = data["details"] as? String ?? ""
            AppLogger.player.error("HLSJSVideoView: fatalError (type=\(errType, privacy: .public), details=\(details, privacy: .public))")
            onEvent?(.fatalError(type: errType, details: details))
            onStateChange?(.error(.hlsParsingFailed("\(errType): \(details)")))

        case .fragLoaded:
            let duration = data["duration"] as? Double ?? 0
            let sn = data["sn"] as? Int ?? 0
            let level = data["level"] as? Int ?? 0
            let loadTime = data["loadTime"] as? Double ?? 0
            onEvent?(.fragLoaded(duration: duration, sn: sn, level: level, loadTime: loadTime))

        case .playStarted:
            let muted = data["muted"] as? Bool ?? false
            let volume = data["volume"] as? Double ?? 1.0
            AppLogger.player.info("HLSJSVideoView: 재생 시작 (muted=\(muted, privacy: .public), volume=\(volume, privacy: .public))")
            onStateChange?(.playing)
        }
    }

    private func parseMetrics(_ data: [String: Any]) -> HLSJSLiveMetrics {
        HLSJSLiveMetrics(
            fps: data["fps"] as? Double ?? 0,
            droppedFrames: data["droppedFrames"] as? Int ?? 0,
            droppedFramesDelta: data["droppedFramesDelta"] as? Int ?? 0,
            bitrateKbps: data["bitrateKbps"] as? Double ?? 0,
            latency: data["latency"] as? Double ?? 0,
            bufferLength: data["bufferLength"] as? Double ?? 0,
            resolution: data["resolution"] as? String,
            playbackRate: Float(data["playbackRate"] as? Double ?? 1.0),
            paused: data["paused"] as? Bool ?? false,
            currentTime: data["currentTime"] as? Double ?? 0,
            bufferHealth: data["bufferHealth"] as? Double ?? 0,
            currentLevel: data["currentLevel"] as? Int ?? -1,
            fragmentDuration: data["fragmentDuration"] as? Double ?? 0,
            timestamp: Date()
        )
    }
}

// MARK: - WKScriptMessageHandler

/// JS→Swift 메시지 핸들러 (weak 참조로 순환 참조 방지)
private final class HLSJSMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var view: HLSJSVideoView?

    init(view: HLSJSVideoView) {
        self.view = view
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        view?.handleMessage(dict)
    }
}
