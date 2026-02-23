// MARK: - PlayerVideoView.swift
// CViewPlayer - VLC / AVPlayer 통합 비디오 렌더링 뷰

import SwiftUI
import AppKit
import CViewCore

/// VLC / AVPlayer 모두 지원하는 통합 비디오 렌더링 SwiftUI 뷰.
/// PlayerEngineProtocol의 `videoView: NSView` 를 컨테이너에 서브뷰로 삽입한다.
/// - VLCPlayerEngine: `playerView` (VLCKitSPM.VLCVideoView) 사용
/// - AVPlayerEngine: `AVPlayerLayerView` (AVPlayerLayer 호스팅 NSView) 사용
///
/// Usage:
/// ```swift
/// PlayerVideoView(videoView: playerVM?.currentVideoView)
/// ```
public struct PlayerVideoView: NSViewRepresentable {
    /// 엔진에서 제공된 렌더링 NSView (PlayerViewModel.currentVideoView)
    public let videoView: NSView?

    public init(videoView: NSView?) {
        self.videoView = videoView
    }

    public func makeNSView(context: Context) -> PlayerContainerView {
        let container = PlayerContainerView()
        if let v = videoView {
            container.setVideoView(v)
        }
        return container
    }

    public func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        // identity 동일하면 레이아웃 패스 완전 스킵 — SwiftUI re-render 시 GPU 불필요한 작업 방지
        if let v = videoView {
            nsView.setVideoView(v)
        } else {
            nsView.clearVideoView()
        }
    }
}

// MARK: - Container NSView

/// 엔진의 videoView를 서브뷰로 관리하는 컨테이너.
///
/// ## GPU 최적화 전략
/// - **AVPlayer**: `AVPlayerLayerView`는 `layer = playerLayer`로 설정되어 playerLayer가
///   뷰의 backing layer 자체. subview로 추가하면 container.layer → playerLayer 2단계만 됨.
/// - **VLC**: VLCVideoView를 subview로 추가 (VLC 내부 drawable 바인딩 구조 유지 필요).
/// - 컨테이너 자체의 CA 암묵적 애니메이션 전면 비활성화.
/// - `layerContentsRedrawPolicy = .never` — 이 NSView는 직접 그리지 않음.
public final class PlayerContainerView: NSView {
    private weak var currentSubview: NSView?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never           // drawRect 완전 차단

        // 컨테이너 자체 레이어 최적화
        let l = layer!
        l.backgroundColor = NSColor.black.cgColor
        l.isOpaque        = true
        l.drawsAsynchronously = false                // 컨테이너는 자체 콘텐츠 없음
        l.shouldRasterize = false
        l.allowsGroupOpacity = false
        // 모든 암묵적 트랜지션 제거 — bounds/position 변경 시 즉시 적용
        l.actions = [
            "position": NSNull(), "bounds":  NSNull(),
            "frame":    NSNull(), "opacity": NSNull(),
            "sublayers": NSNull(), "backgroundColor": NSNull(),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    public func setVideoView(_ videoView: NSView) {
        guard videoView !== currentSubview else { return }

        currentSubview?.removeFromSuperview()
        currentSubview = nil

        addSubview(videoView)
        videoView.frame = bounds
        videoView.autoresizingMask = [.width, .height]
        currentSubview = videoView
    }

    public func clearVideoView() {
        currentSubview?.removeFromSuperview()
        currentSubview = nil
    }

    public override func layout() {
        super.layout()
        currentSubview?.frame = bounds
    }
}

