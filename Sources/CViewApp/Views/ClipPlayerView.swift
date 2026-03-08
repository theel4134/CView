// MARK: - ClipPlayerView.swift
// 클립 재생 화면 — AVPlayer 직접 재생 + embed WebView fallback

import SwiftUI
import WebKit
import CViewCore
import CViewUI
import CViewPlayer

/// 클립 재생 뷰
struct ClipPlayerView: View {

    let clipInfo: ClipInfo
    @State private var viewModel = ClipPlayerViewModel()
    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── embed WebView fallback (ABR_HLS 등 직접 재생 불가 시)
            if let embedURL = viewModel.embedFallbackURL {
                ClipEmbedWebView(
                    url: embedURL,
                    onVideoURLExtracted: { url in
                        Task { await viewModel.switchToVLCPlayer(streamURL: url, clipUID: clipInfo.clipUID) }
                    }
                )
                .ignoresSafeArea()
                embedTitleBar
            } else {
                // ── VLC 직접 재생
                if let engine = viewModel.playerEngine {
                    VLCVideoView(playerEngine: engine)
                        .ignoresSafeArea()
                }

                // Loading (초기 로딩만 표시 — .buffering은 재생 중 버퍼링이므로 오버레이 미표시)
                if viewModel.playbackState == .loading {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            Text("클립 로딩 중...")
                                .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }

                // Error
                if case .error(let msg) = viewModel.playbackState {
                    errorOverlay(msg)
                }

                // Ended
                if viewModel.playbackState == .ended {
                    endedOverlay
                }

                // Controls (에러/종료 상태에서는 미표시)
                if showControls && viewModel.playerEngine != nil && viewModel.isPlaybackActive {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .background(.black)
        .onAppear {
            viewModel = ClipPlayerViewModel(apiClient: appState.apiClient)
            Task { await viewModel.startClip(from: clipInfo) }
        }
        .onDisappear {
            controlsTimer?.cancel()
            viewModel.stop()
        }
        .onHover { hovering in
            if viewModel.embedFallbackURL == nil && viewModel.isPlaybackActive {
                withAnimation(DesignTokens.Animation.fast) { showControls = hovering }
                if hovering { resetControlsTimer() }
            }
        }
        .onTapGesture {
            if viewModel.embedFallbackURL == nil && viewModel.isPlaybackActive {
                withAnimation(DesignTokens.Animation.fast) { showControls.toggle() }
                if showControls { resetControlsTimer() }
            }
        }
        .navigationTitle(viewModel.clipTitle.isEmpty ? clipInfo.clipTitle : viewModel.clipTitle)
        .frame(minWidth: 640, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    if let url = URL(string: "https://chzzk.naver.com/clips/\(clipInfo.clipUID)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("치지직에서 열기")
            }
        }
    }

    // MARK: - AVPlayer Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Top gradient + title
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.clipTitle)
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .lineLimit(1)
                    if !viewModel.channelName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            Text(viewModel.channelName)
                                .font(DesignTokens.Typography.caption)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                LinearGradient(colors: [.black.opacity(0.75), .clear],
                               startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // Center play/pause
            Button { viewModel.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                        .overlay { Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5) }
                    Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(DesignTokens.Typography.custom(size: 24, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Bottom controls + timeline
            VStack(spacing: 6) {
                TimelineSlider(
                    currentTime: $viewModel.currentTime,
                    duration: viewModel.duration,
                    onSeek: { viewModel.seek(to: $0) }
                )

                HStack(spacing: 14) {
                    Button { viewModel.seekRelative(-10) } label: {
                        Image(systemName: "gobackward.10").font(DesignTokens.Typography.body)
                    }
                    .buttonStyle(.plain)

                    Button { viewModel.togglePlayPause() } label: {
                        Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                            .font(DesignTokens.Typography.custom(size: 15))
                    }
                    .buttonStyle(.plain)

                    Button { viewModel.seekRelative(10) } label: {
                        Image(systemName: "goforward.10").font(DesignTokens.Typography.body)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 4) {
                        Button { viewModel.toggleMute() } label: {
                            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(DesignTokens.Typography.captionMedium)
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { Double(viewModel.volume) },
                            set: { viewModel.setVolume(Float($0)) }
                        ), in: 0...1)
                        .frame(width: 72)
                        .controlSize(.small)
                    }

                    Text("\(ClipPlayerViewModel.formatTime(viewModel.currentTime)) / \(ClipPlayerViewModel.formatTime(viewModel.duration))")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))

                    Spacer()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
    }

    // MARK: - Embed title bar

    private var embedTitleBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // 썸네일 미리보기
                if let thumbURL = clipInfo.thumbnailImageURL {
                    CachedAsyncImage(url: thumbURL) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(.ultraThinMaterial)
                    }
                    .frame(width: 56, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.clipTitle.isEmpty ? clipInfo.clipTitle : viewModel.clipTitle)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let channel = clipInfo.channel {
                            if let avatarURL = channel.channelImageURL {
                                CachedAsyncImage(url: avatarURL) {
                                    Circle().fill(.ultraThinMaterial)
                                }
                                .frame(width: 16, height: 16)
                                .clipShape(Circle())
                            }
                            Text(channel.channelName)
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(.white.opacity(0.6))
                        } else if !viewModel.channelName.isEmpty {
                            Text(viewModel.channelName)
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if clipInfo.readCount > 0 {
                            Text("·")
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(.white.opacity(0.4))
                            Image(systemName: "eye.fill")
                                .font(DesignTokens.Typography.custom(size: 8))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(formattedCount(clipInfo.readCount))
                                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                LinearGradient(colors: [.black.opacity(0.75), .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            Spacer()
        }
    }

    private func formattedCount(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.1f만", Double(count) / 10_000) }
        return "\(count)"
    }

    // MARK: - Error / Ended

    @ViewBuilder
    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.custom(size: 40))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                HStack(spacing: 12) {
                    Button("다시 시도") {
                        Task { await viewModel.startClip(from: clipInfo) }
                    }
                    .buttonStyle(CViewButtonStyle())
                    Button("치지직에서 열기") {
                        if let url = URL(string: "https://chzzk.naver.com/clips/\(clipInfo.clipUID)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                }
            }
        }
    }

    private var endedOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 14) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(DesignTokens.Typography.custom(size: 48))
                    .foregroundStyle(.white.opacity(0.85))
                Text("재생 완료")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                Button("다시 재생") { viewModel.togglePlayPause() }
                    .buttonStyle(CViewButtonStyle())
            }
        }
    }

    // MARK: - Timer

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(DesignTokens.Animation.normal) { showControls = false }
                }
            }
        }
    }
}

// MARK: - Embed WebView

/// 치지직 embed 클립 재생용 WKWebView (ABR_HLS fallback)
/// chzzk.naver.com의 HTML5 플레이어를 직접 표시하여 ABR_HLS 클립을 재생합니다.
/// WKWebsiteDataStore.default()를 사용해 앱의 로그인 세션(쿠키)을 공유합니다.
/// XHR/fetch를 인터셉트하여 .m3u8 URL을 추출, VLC로 전환합니다.
private struct ClipEmbedWebView: NSViewRepresentable {
    let url: URL
    var onVideoURLExtracted: ((URL) -> Void)? = nil

    /// React SPA 로드 완료 후 자동재생 시도 스크립트 (최대 30회 = 15초)
    private static let autoplayScript = WKUserScript(
        source: """
        (function() {
            var attempts = 0;
            function tryPlay() {
                var v = document.querySelector('video');
                if (v) {
                    v.muted = false;
                    v.volume = 1.0;
                    try { v.play(); } catch(e) {}
                    return;
                }
                if (++attempts < 30) setTimeout(tryPlay, 500);
            }
            setTimeout(tryPlay, 1500);
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )

    /// 포괄적인 m3u8 URL 인터셉션 스크립트
    /// - HTMLMediaElement.src 세터 패치 (WebKit 네이티브 HLS)
    /// - XHR.open 패치 (직접 m3u8 요청)
    /// - XHR 응답 바디 스캔 (rmcnmv/neonplayer API)
    /// - fetch 패치 (직접 m3u8 요청 + 응답 바디 스캔)
    /// - MutationObserver + 주기적 폴링 (video.currentSrc)
    private static let m3u8InterceptScript = WKUserScript(
        source: """
        (function() {
            'use strict';
            if (window.__naverM3U8Reported) return;

            function report(url) {
                if (window.__naverM3U8Reported) return;
                if (!url || typeof url !== 'string') return;
                if (url.indexOf('blob:') !== -1) return;
                if (!url.match(/^https?:\\/\\//)) return;
                window.__naverM3U8Reported = true;
                try { window.webkit.messageHandlers.m3u8URL.postMessage(url); } catch(e) {}
            }

            function isM3U8(url) {
                return url && url.indexOf('.m3u8') !== -1;
            }

            function extractM3U8FromText(text) {
                if (!text || typeof text !== 'string') return;
                var m = text.match(/https?:\\/\\/[^\\s"',<>\\[\\]{}()|\\\\]+\\.m3u8[^\\s"',<>\\[\\]{}()|\\\\]*/);
                if (m) { report(m[0]); return; }
                // "source":"url" 패턴 탐색 (Naver VOD JSON 응답)
                var s = text.match(/"source"\\s*:\\s*"(https?:\\/\\/[^"]+)"/);
                if (s) { report(s[1]); }
            }

            function isVideoAPI(url) {
                return url && (
                    url.indexOf('rmcnmv') !== -1 ||
                    url.indexOf('neonplayer') !== -1 ||
                    url.indexOf('nnavervod') !== -1 ||
                    url.indexOf('apis.naver.com') !== -1 ||
                    url.indexOf('videocloud') !== -1
                );
            }

            // ── Patch 1: HTMLMediaElement.prototype.src (WebKit 네이티브 HLS 대응) ──
            try {
                var srcDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
                if (srcDesc && srcDesc.set) {
                    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
                        get: srcDesc.get,
                        set: function(val) {
                            if (isM3U8(val) && val.indexOf('blob:') === -1) { report(val); }
                            return srcDesc.set.call(this, val);
                        },
                        configurable: true
                    });
                }
            } catch(e) {}

            // ── Patch 2: Element.setAttribute (src attribute로 설정 시) ────────────
            try {
                var origSetAttr = Element.prototype.setAttribute;
                Element.prototype.setAttribute = function(name, value) {
                    if (name === 'src' && (this.tagName === 'VIDEO' || this.tagName === 'SOURCE') &&
                        isM3U8(value) && value.indexOf('blob:') === -1) {
                        report(value);
                    }
                    return origSetAttr.call(this, name, value);
                };
            } catch(e) {}

            // ── Patch 3: XMLHttpRequest ─────────────────────────────────────────────
            try {
                var _open = XMLHttpRequest.prototype.open;
                var _send = XMLHttpRequest.prototype.send;

                XMLHttpRequest.prototype.open = function(method, url) {
                    var urlStr = typeof url === 'string' ? url : String(url);
                    this.__xUrl = urlStr;
                    if (isM3U8(urlStr) && urlStr.indexOf('blob:') === -1) { report(urlStr); }
                    return _open.apply(this, arguments);
                };

                XMLHttpRequest.prototype.send = function(body) {
                    var url = this.__xUrl || '';
                    if (isVideoAPI(url)) {
                        var self = this;
                        self.addEventListener('readystatechange', function() {
                            if (self.readyState === 4 && self.status === 200) {
                                extractM3U8FromText(self.responseText);
                            }
                        });
                    }
                    return _send.apply(this, arguments);
                };
            } catch(e) {}

            // ── Patch 4: fetch ──────────────────────────────────────────────────────
            try {
                if (typeof window.fetch === 'function') {
                    var _fetch = window.fetch;
                    window.fetch = function(input, init) {
                        var url = '';
                        if (typeof input === 'string') {
                            url = input;
                        } else if (input instanceof URL) {
                            url = input.href;
                        } else if (input && typeof input.url === 'string') {
                            url = input.url;
                        } else if (input && typeof input.toString === 'function') {
                            url = input.toString();
                        }
                        if (isM3U8(url) && url.indexOf('blob:') === -1) { report(url); }
                        var promise = _fetch.apply(this, arguments);
                        if (isVideoAPI(url)) {
                            promise = promise.then(function(resp) {
                                var clone = resp.clone();
                                clone.text().then(extractM3U8FromText).catch(function(){});
                                return resp;
                            });
                        }
                        return promise;
                    };
                }
            } catch(e) {}

            // ── Patch 5: MutationObserver + 주기적 폴링 (video.currentSrc) ─────────
            function checkVideoElement(v) {
                var src = v.currentSrc || v.src;
                if (isM3U8(src) && src.indexOf('blob:') === -1) {
                    report(src);
                    return;
                }
                v.addEventListener('loadstart', function checkSrc() {
                    var s = v.currentSrc || v.src;
                    if (isM3U8(s) && s.indexOf('blob:') === -1) { report(s); }
                    v.removeEventListener('loadstart', checkSrc);
                });
            }

            try {
                new MutationObserver(function(muts) {
                    for (var i = 0; i < muts.length; i++) {
                        var nodes = muts[i].addedNodes;
                        for (var j = 0; j < nodes.length; j++) {
                            var n = nodes[j];
                            if (n.tagName === 'VIDEO') { checkVideoElement(n); }
                            if (n.querySelectorAll) {
                                var vs = n.querySelectorAll('video');
                                for (var k = 0; k < vs.length; k++) { checkVideoElement(vs[k]); }
                            }
                        }
                    }
                }).observe(document.documentElement || document, { childList: true, subtree: true });
            } catch(e) {}

            var pollTimer = setInterval(function() {
                if (window.__naverM3U8Reported) { clearInterval(pollTimer); return; }
                var vs = document.querySelectorAll('video');
                for (var i = 0; i < vs.length; i++) { checkVideoElement(vs[i]); }
            }, 1000);
            setTimeout(function() { clearInterval(pollTimer); }, 60000);
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoURLExtracted: onVideoURLExtracted)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // 앱의 로그인 세션 쿠키(NID_AUT, NID_SES 등)를 공유하기 위해 default data store 사용
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsAirPlayForMediaPlayback = true
        // 인터셉션 스크립트는 atDocumentStart에 먼저 주입
        cfg.userContentController.addUserScript(ClipEmbedWebView.m3u8InterceptScript)
        cfg.userContentController.addUserScript(ClipEmbedWebView.autoplayScript)
        cfg.userContentController.add(context.coordinator, name: "m3u8URL")

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator

        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif

        var req = URLRequest(url: url)
        req.setValue("https://chzzk.naver.com", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        webView.load(req)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "m3u8URL")
        nsView.navigationDelegate = nil
        nsView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onVideoURLExtracted: ((URL) -> Void)?
        private var reloadCount = 0
        private var pollTask: Task<Void, Never>?
        private var urlReported = false

        init(onVideoURLExtracted: ((URL) -> Void)?) {
            self.onVideoURLExtracted = onVideoURLExtracted
        }

        deinit { pollTask?.cancel() }

        // MARK: - WKScriptMessageHandler (m3u8 URL 수신)

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !urlReported,
                  message.name == "m3u8URL",
                  let urlString = message.body as? String,
                  let url = URL(string: urlString) else { return }
            urlReported = true
            pollTask?.cancel()
            DispatchQueue.main.async { [weak self] in
                self?.onVideoURLExtracted?(url)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // React SPA가 초기화된 후 video.currentSrc를 주기적으로 확인
            // (native HLS: video.src가 m3u8 URL, HLS.js+MSE: blob: URL)
            pollTask?.cancel()
            pollTask = Task { [weak self, weak webView] in
                guard let self else { return }
                // 최대 20회, 1.5초 간격 = 30초
                for _ in 0..<20 {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled, !self.urlReported else { return }
                    guard let wv = webView else { return }

                    await MainActor.run {
                        // 자동재생 시도
                        wv.evaluateJavaScript("""
                        (function(){
                            var v = document.querySelector('video');
                            if (v) { v.muted=false; v.volume=1.0; try{v.play();}catch(e){} }
                        })();
                        """)
                        // video.currentSrc 추출 시도
                        wv.evaluateJavaScript("""
                        (function(){
                            var v = document.querySelector('video');
                            if (!v) return null;
                            var s = v.currentSrc || v.src || '';
                            return (s.indexOf('.m3u8') !== -1 && s.indexOf('blob:') === -1) ? s : null;
                        })();
                        """) { [weak self] result, _ in
                            guard let self, !self.urlReported else { return }
                            if let urlStr = result as? String,
                               let url = URL(string: urlStr) {
                                self.urlReported = true
                                self.pollTask?.cancel()
                                self.onVideoURLExtracted?(url)
                            }
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if reloadCount < 1 {
                reloadCount += 1
                webView.reload()
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}

