// MARK: - VLCVideoView.swift
// CViewPlayer — VLC Video NSViewRepresentable (SwiftUI)
//
// [아키텍처 원칙]
// VLCPlayerEngine은 자신만의 VLCKitSPM.VLCVideoView(playerView)를 소유한다.
// VLCMediaPlayer는 play() 직전 MainActor에서 setVideoView(playerView)로 바인딩된다.
//
// 이 NSViewRepresentable은 NSView container를 관리하고,
// engine.playerView를 container의 서브뷰로 삽입/교체한다.
//
// [왜 container 방식인가?]
// NSViewRepresentable은 makeNSView에서 한 번 생성된 NSView를 SwiftUI가 계속 재사용한다.
// engine이 교체(stopStream→startStream)될 때 새 engine의 playerView를 서브뷰로 swap할 수 있도록
// container(outer NSView)를 유지하며 그 안의 playerView만 교체한다.
//
// [drawable/setVideoView 관리 제거]
// 이전 방식: NSViewRepresentable이 player.drawable = view 를 호출 (타이밍 경쟁 조건 발생).
// 현재 방식: 엔진이 playerView를 소유하고 play() 직전 setVideoView 확정 → drawable 관리 불필요.

import SwiftUI
import AppKit
@preconcurrency import VLCKitSPM

// MARK: - VLC Video View (SwiftUI)

public struct VLCVideoView: NSViewRepresentable {
    /// ✅ container NSView를 사용. engine.playerView는 그 안에 서브뷰로 삽입됨.
    public typealias NSViewType = NSView

    private let playerEngine: VLCPlayerEngine?

    public init(playerEngine: VLCPlayerEngine?) {
        self.playerEngine = playerEngine
    }

    // MARK: - Coordinator

    public final class Coordinator {
        /// 마지막으로 container에 연결된 엔진 (동일 엔진이면 서브뷰 교체 스킵)
        weak var boundEngine: VLCPlayerEngine?
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - NSViewRepresentable

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        if let engine = playerEngine {
            attach(engine.playerView, to: container)
            context.coordinator.boundEngine = engine
        }

        return container
    }

    public func updateNSView(_ container: NSView, context: Context) {
        guard let engine = playerEngine else {
            // 엔진 해제(stop) 시 서브뷰 정리
            container.subviews.forEach { $0.removeFromSuperview() }
            context.coordinator.boundEngine = nil
            return
        }

        // 동일 엔진이면 서브뷰 재교체 불필요
        if context.coordinator.boundEngine === engine { return }

        // 새 엔진으로 교체: 기존 서브뷰 제거 후 새 playerView 삽입
        container.subviews.forEach { $0.removeFromSuperview() }
        attach(engine.playerView, to: container)
        context.coordinator.boundEngine = engine
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // container 서브뷰 정리 (엔진은 별도 deinit에서 stop)
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Private Helpers

    private func attach(_ playerView: VLCKitSPM.VLCVideoView, to container: NSView) {
        // Auto Layout으로 container를 꽉 채움 (makeNSView 시 frame이 zero일 수 있으므로
        // autoresizingMask 프레임 세팅보다 Auto Layout이 더 안정적)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - VLCVideoContainerView (PiPController 호환 wrapper)
    public final class VLCVideoContainerView: NSObject {
        public let vlcNativeView: VLCNativePlayerView
        override public init() {
            vlcNativeView = VLCNativePlayerView()
            super.init()
        }
    }
}

// MARK: - VLCNativePlayerView (PiPController 전용)

/// PiPController에서 사용하는 VLC PiP 뷰.
/// PiP 패널 NSWindow에 삽입된 후 setPlayer()로 drawable 연결.
public final class VLCNativePlayerView: NSView {

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    private weak var pipBoundPlayer: VLCMediaPlayer?

    public func setPlayer(_ player: VLCMediaPlayer?) {
        pipBoundPlayer = player
        if window != nil { applyPiPDrawable() }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { applyPiPDrawable() }
    }

    private func applyPiPDrawable() {
        guard let player = pipBoundPlayer else { return }
        if player.drawable as? VLCNativePlayerView === self { return }
        player.drawable = self
    }
}
