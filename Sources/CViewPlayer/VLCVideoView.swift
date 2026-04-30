// MARK: - VLCVideoView.swift
// CViewPlayer — VLC Video NSViewRepresentable (SwiftUI)
//
// [아키텍처 원칙]
// VLCPlayerEngine은 자신만의 VLCLayerHostView(playerView)를 소유한다.
// VLCLayerHostView는 NSView 컨테이너로, VLC가 내부적으로 렌더링 서피스를
// 생성하여 이 뷰의 서브뷰로 추가한다.
// VLCMediaPlayer.drawable = playerView 로 설정하면 정상 렌더링.
//
// 이 NSViewRepresentable은 NSView container를 관리하고,
// engine.playerView(VLCLayerHostView)를 container의 서브뷰로 삽입/교체한다.
//
// [왜 container 방식인가?]
// NSViewRepresentable은 makeNSView에서 한 번 생성된 NSView를 SwiftUI가 계속 재사용한다.
// engine이 교체(stopStream→startStream)될 때 새 engine의 playerView를 서브뷰로 swap할 수 있도록
// container(outer NSView)를 유지하며 그 안의 playerView만 교체한다.
//
// [drawable 관리]
// 엔진이 playerView를 소유하고 play() 직전 player.drawable = playerView 확정
// → NSViewRepresentable에서 drawable 관리 불필요.

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
        container.layerContentsRedrawPolicy = .never     // drawRect 차단 — 리사이즈 시 불필요한 redraw 방지
        container.canDrawSubviewsIntoLayer = true        // 서브뷰 레이어 합성 플래트닝
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.isOpaque = true
        // 리사이즈 시 CA 암묵적 애니메이션 제거
        container.layer?.actions = [
            "position": NSNull(), "bounds": NSNull(),
            "frame": NSNull(), "sublayers": NSNull(),
        ]

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

    private func attach(_ playerView: VLCLayerHostView, to container: NSView) {
        // autoresizingMask로 container 꽉 채움 — Auto Layout constraint solver 비용 제거
        // 리사이즈 시 매 프레임 constraint 재계산 대신 즉시 프레임 추종
        playerView.translatesAutoresizingMaskIntoConstraints = true
        playerView.frame = container.bounds
        playerView.autoresizingMask = [.width, .height]
        container.addSubview(playerView)
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
