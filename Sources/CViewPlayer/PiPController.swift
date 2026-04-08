// MARK: - PiPController.swift
// CViewPlayer - Picture-in-Picture 컨트롤러
// 플로팅 NSPanel 기반 PiP 지원 — 마우스오버 컨트롤, 위치기억, 강제복귀, 퀵액션

import AppKit
import SwiftUI
import AVFoundation
import CViewCore
@preconcurrency import VLCKitSPM

/// PiP 상태
public enum PiPState: Sendable {
    case inactive
    case active
    case transitioning
}

// MARK: - PiP Hover Controls View

/// PiP 패널 위 마우스오버 컨트롤 오버레이 (NSHostingView 기반)
///
/// [크래시 방지 설계]
/// macOS 26(Sequoia)에서 AppKit은 constraint update 사이클 중 constraint 재진입을
/// EXC_BREAKPOINT로 강제 종료한다. 이를 방지하기 위해 NSHostingView를 한 번만 생성하고
/// alphaValue로만 가시성을 제어한다. 마우스 이벤트 핸들러에서 subview를 추가/제거하거나
/// NSLayoutConstraint.activate()를 호출하면 진행 중인 layout/display cycle에 재진입하여
/// 재귀 constraint 갱신 크래시가 발생한다.
private final class PiPHoverControlsView: NSView {

    private var trackingArea: NSTrackingArea?
    // NSHostingView는 초기화 시 한 번만 생성되어 유지됨 — 절대 제거/재생성 금지
    private var hostingView: NSHostingView<PiPControlsSwiftUIView>?
    var onClose: (() -> Void)?
    var onReturnToMain: (() -> Void)?
    var onToggleMute: (() -> Void)?
    var isMuted: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        autoresizingMask = [.width, .height]
        setupHostingView()
        setupTrackingArea()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTrackingArea() {
        trackingArea.map { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// NSHostingView를 한 번만 생성하고 constraints를 설정한다.
    /// 이후에는 alphaValue만 변경하여 가시성을 제어한다.
    private func setupHostingView() {
        guard hostingView == nil else { return }

        let controls = PiPControlsSwiftUIView(
            onClose: { [weak self] in self?.onClose?() },
            onReturnToMain: { [weak self] in self?.onReturnToMain?() },
            onToggleMute: { [weak self] in self?.onToggleMute?() },
            isMuted: isMuted
        )
        let hosting = NSHostingView(rootView: controls)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // 초기에는 투명하게 시작
        hosting.alphaValue = 0
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hostingView = hosting
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            hostingView?.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            hostingView?.animator().alphaValue = 0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }
}

// MARK: - PiP Controls SwiftUI View

private struct PiPControlsSwiftUIView: View {
    let onClose: () -> Void
    let onReturnToMain: () -> Void
    let onToggleMute: () -> Void
    let isMuted: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 상단 그라디언트
            LinearGradient(
                colors: [.black.opacity(0.65), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 60)
            .frame(maxHeight: .infinity, alignment: .top)

            // 컨트롤 버튼
            HStack(spacing: 8) {
                // 음소거
                pipButton(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: isMuted ? "소리 켜기" : "음소거") {
                    onToggleMute()
                }
                // 메인 창 복귀
                pipButton(icon: "arrow.up.backward.and.arrow.down.forward", help: "메인 창으로 복귀") {
                    onReturnToMain()
                }
                // PiP 닫기
                pipButton(icon: "xmark", help: "PiP 닫기", isDestructive: true) {
                    onClose()
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .allowsHitTesting(true)
    }

    private func pipButton(icon: String, help: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(isDestructive ? .red : .white)
                .frame(width: 28, height: 28)
                .background(DesignTokens.Colors.surfaceElevated)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - PiP Panel Delegate (위치·크기 기억)

private final class PiPPanelDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return true
    }
}

// MARK: - PiP Controller

/// PiP 컨트롤러 — 플로팅 패널 기반 PiP 지원
@MainActor
public final class PiPController: @unchecked Sendable {

    // MARK: - Properties

    private var pipPanel: NSPanel?
    private var panelDelegate: PiPPanelDelegate?
    private var currentEngine: (any PlayerEngineProtocol)?
    private var originalDrawable: NSView?
    private let logger = AppLogger.player

    /// 마지막 PiP 창 위치·크기 (재사용)
    private var savedPanelFrame: NSRect?

    public private(set) var state: PiPState = .inactive

    /// PiP 패널 기본 크기
    private let defaultSize = NSSize(width: 400, height: 225)
    private let minSize = NSSize(width: 280, height: 158)

    /// 현재 채널 음소거 여부 (HoverControls에 전달)
    public var isMuted: Bool = false
    public var onToggleMute: (() -> Void)?
    public var onReturnToMain: (() -> Void)?

    /// PiP 종료 시 외부 알림 콜백 (stopPiP / 패널 닫기 모두 호출)
    public var onPiPStopped: (() -> Void)?

    // MARK: - Singleton

    public static let shared = PiPController()
    private init() {}

    // MARK: - Public API

    /// VLC 엔진으로 PiP 시작
    public func startPiP(vlcEngine: VLCPlayerEngine, title: String = "PiP") {
        guard state == .inactive else {
            // 이미 활성 시 창 전면으로 가져옴
            pipPanel?.orderFront(nil)
            return
        }

        state = .transitioning
        currentEngine = vlcEngine
        originalDrawable = vlcEngine.mediaPlayer.drawable as? NSView

        let panel = createPanel(title: title)

        // VLC 플레이어 뷰 — VLCNativePlayerView를 패널에 추가 후 drawable 연결
        let vlcView = VLCNativePlayerView()
        setupPanelContent(panel: panel, videoView: vlcView)

        pipPanel = panel
        panel.orderFront(nil)
        // 패널이 NSWindow 계층에 진입한 후 setPlayer → drawable 설정 → VLC vout 정상 초기화
        vlcView.setPlayer(vlcEngine.mediaPlayer)
        state = .active

        logger.info("PiP started (VLC): \(title)")
    }

    /// AVPlayer 엔진으로 PiP 시작
    public func startPiP(avEngine: AVPlayerEngine, title: String = "PiP") {
        guard state == .inactive else {
            pipPanel?.orderFront(nil)
            return
        }

        state = .transitioning
        currentEngine = avEngine

        let panel = createPanel(title: title)

        let avView = AVVideoView.AVVideoNSView()
        avView.setPlayer(avEngine.player)
        setupPanelContent(panel: panel, videoView: avView)

        pipPanel = panel
        panel.orderFront(nil)
        state = .active

        logger.info("PiP started (AVPlayer): \(title)")
    }

    /// PiP 종료 (원본 drawable 복원 포함)
    public func stopPiP() {
        guard state != .inactive else { return }

        state = .transitioning

        // 패널 닫히기 전 위치 저장
        if let frame = pipPanel?.frame { savedPanelFrame = frame }

        restoreOriginalDrawable()

        pipPanel?.close()
        pipPanel = nil
        panelDelegate = nil
        currentEngine = nil
        originalDrawable = nil

        state = .inactive
        logger.info("PiP stopped")

        let callback = onPiPStopped
        onPiPStopped = nil
        callback?()
    }

    /// PiP 토글
    public func togglePiP(vlcEngine: VLCPlayerEngine?, avEngine: AVPlayerEngine?, title: String = "PiP") {
        if state == .active {
            stopPiP()
        } else if state == .inactive {
            if let vlc = vlcEngine {
                startPiP(vlcEngine: vlc, title: title)
            } else if let av = avEngine {
                startPiP(avEngine: av, title: title)
            }
        }
    }

    /// PiP 활성 여부
    public var isActive: Bool { state == .active }

    /// PiP 창을 메인 창 위로 가져옴
    public func bringToFront() {
        pipPanel?.orderFront(nil)
    }

    // MARK: - Panel Setup

    private func setupPanelContent(panel: NSPanel, videoView: NSView) {
        let containerView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        videoView.autoresizingMask = [.width, .height]
        videoView.frame = containerView.bounds
        containerView.addSubview(videoView)

        // 마우스오버 컨트롤 레이어
        let hoverControls = PiPHoverControlsView(frame: containerView.bounds)
        hoverControls.onClose = { [weak self] in Task { @MainActor in self?.stopPiP() } }
        hoverControls.onReturnToMain = { [weak self] in Task { @MainActor in self?.returnToMainWindow() } }
        hoverControls.onToggleMute = { [weak self] in Task { @MainActor in self?.onToggleMute?() } }
        hoverControls.isMuted = isMuted
        containerView.addSubview(hoverControls)

        panel.contentView = containerView
    }

    private func returnToMainWindow() {
        NSApp.mainWindow?.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onReturnToMain?()
    }

    private func restoreOriginalDrawable() {
        if let vlcEngine = currentEngine as? VLCPlayerEngine, let original = originalDrawable {
            vlcEngine.mediaPlayer.drawable = original
        }
    }

    // MARK: - Panel Creation

    private func createPanel(title: String) -> NSPanel {
        pipPanel?.close()

        let originRect: NSRect
        if let saved = savedPanelFrame {
            originRect = saved
        } else {
            originRect = NSRect(origin: defaultPosition(), size: defaultSize)
        }

        let panel = NSPanel(
            contentRect: originRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.minSize = minSize
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.aspectRatio = NSSize(width: 16, height: 9)

        // Delegate
        let delegate = PiPPanelDelegate()
        delegate.onClose = { [weak self] in
            Task { @MainActor in
                self?.savedPanelFrame = self?.pipPanel?.frame
                self?.handlePanelClose()
            }
        }
        panel.delegate = delegate
        panelDelegate = delegate

        return panel
    }

    private func defaultPosition() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let f = screen.visibleFrame
        return NSPoint(x: f.maxX - defaultSize.width - 20, y: f.minY + 20)
    }

    private func handlePanelClose() {
        restoreOriginalDrawable()
        state = .inactive
        currentEngine = nil
        originalDrawable = nil
        pipPanel = nil
        panelDelegate = nil
        logger.info("PiP panel closed by user")

        let callback = onPiPStopped
        onPiPStopped = nil
        callback?()
    }
}
