// MARK: - PlayerVideoView.swift
// CViewPlayer - VLC / AVPlayer 통합 비디오 렌더링 뷰

import SwiftUI
import AppKit
import CViewCore
import VLCKitSPM

/// VLC / AVPlayer 모두 지원하는 통합 비디오 렌더링 SwiftUI 뷰.
/// PlayerEngineProtocol의 `videoView: NSView` 를 컨테이너에 서브뷰로 삽입한다.
/// - VLCPlayerEngine: `playerView` (VLCLayerHostView — NSView 컨테이너) 사용
///   → VLC가 렌더링 서피스를 내부 생성하여 서브뷰로 추가
/// - AVPlayerEngine: `AVPlayerLayerView` (AVPlayerLayer 호스팅 NSView) 사용
///
/// Usage:
/// ```swift
/// PlayerVideoView(videoView: playerVM?.currentVideoView)
/// ```
public struct PlayerVideoView: NSViewRepresentable {
    /// 엔진에서 제공된 렌더링 NSView (PlayerViewModel.currentVideoView)
    public let videoView: NSView?
    /// true이면 aspect-fill (화면 꽉 채움, 가장자리 잘림 허용), false이면 aspect-fit (레터박스)
    public let fill: Bool

    public init(videoView: NSView?, fill: Bool = false) {
        self.videoView = videoView
        self.fill = fill
    }

    public func makeNSView(context: Context) -> PlayerContainerView {
        let container = PlayerContainerView()
        if let v = videoView {
            container.setVideoView(v)
        }
        container.setFillMode(fill)
        return container
    }

    public func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        // identity 동일하면 레이아웃 패스 완전 스킵 — SwiftUI re-render 시 GPU 불필요한 작업 방지
        if let v = videoView {
            nsView.setVideoView(v)
        } else {
            nsView.clearVideoView()
        }
        nsView.setFillMode(fill)
    }
}

// MARK: - Container NSView

/// 엔진의 videoView를 서브뷰로 관리하는 컨테이너.
///
/// ## GPU 최적화 전략
/// - **AVPlayer**: `AVPlayerLayerView`는 `layer = playerLayer`로 설정되어 playerLayer가
///   뷰의 backing layer 자체. subview로 추가하면 container.layer → playerLayer 2단계만 됨.
/// - **VLC**: VLCLayerHostView를 subview로 추가.
///   VLC 렌더링 서피스가 VLCLayerHostView 내부에 임베딩.
/// - 컨테이너 자체의 CA 암묵적 애니메이션 전면 비활성화.
/// - `layerContentsRedrawPolicy = .never` — 이 NSView는 직접 그리지 않음.
///
/// [크래시 방지] layout() 중 subview 교체는 constraint 재진입 크래시를 유발한다.
/// isLayingOut 플래그로 layout() 실행 중 setVideoView() 호출을 다음 RunLoop으로 지연시킨다.
public final class PlayerContainerView: NSView {
    private weak var currentSubview: NSView?
    private var isFillMode: Bool = false
    /// layout() 재진입 방지 플래그
    private var isLayingOut: Bool = false
    /// layout() 중 요청된 pending videoView 교체
    private weak var pendingVideoView: NSView?

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
        // Retina 대응 — 서브레이어 합성 시 올바른 스케일 적용
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        // 비디오 렌더링이 컨테이너 밖으로 넘치지 않도록 클리핑
        // NavigationSplitView 사이드바 뒤로 영상이 보이는 현상 방지
        l.masksToBounds = true
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

        // layout() 실행 중 subview 교체는 constraint 재진입 크래시를 유발한다.
        // 다음 RunLoop 사이클로 지연시킨다.
        if isLayingOut {
            pendingVideoView = videoView
            return
        }

        attachVideoView(videoView)
    }

    private func attachVideoView(_ videoView: NSView) {
        guard videoView !== currentSubview else { return }

        currentSubview?.removeFromSuperview()
        currentSubview = nil

        addSubview(videoView)
        videoView.frame = bounds
        videoView.autoresizingMask = [.width, .height]

        // VLCLayerHostView — VLC가 생성한 렌더링 서브뷰 포함 클리핑
        if let sublayer = videoView.layer {
            sublayer.masksToBounds = true
        }

        currentSubview = videoView
        // 새 비디오 뷰에 현재 fill 모드 반영
        applyFillMode(to: videoView)

        // bounds가 유효한 경우 즉시 needsLayout을 예약하여
        // 다음 layout 패스에서 videoView.frame = bounds 가 적용되도록 한다.
        // makeNSView 시 bounds == .zero이면 layout() 에서 자동 처리됨.
        if bounds.size != .zero {
            needsLayout = true
        }
    }

    public func clearVideoView() {
        pendingVideoView = nil
        currentSubview?.removeFromSuperview()
        currentSubview = nil
    }

    /// 비디오 화면 채움 모드 설정 (true: aspect-fill, false: aspect-fit)
    public func setFillMode(_ fill: Bool) {
        guard isFillMode != fill else { return }
        isFillMode = fill
        guard let subview = currentSubview else { return }
        applyFillMode(to: subview)
    }

    private func applyFillMode(to videoView: NSView) {
        // AVVideoNSView인 경우 (AVPlayerLayer 기반)
        if let avView = videoView as? AVVideoView.AVVideoNSView {
            avView.setFillMode(isFillMode)
        }
        // VLC: 렌더링 서피스를 서브뷰로 생성하므로
        // gravity 변경은 VLC API(mediaPlayer.videoAspectRatio 등)로 처리 필요
    }

    public override func layout() {
        isLayingOut = true
        super.layout()
        currentSubview?.frame = bounds
        isLayingOut = false

        // layout() 중 요청된 videoView 교체를 안전하게 처리
        if let pending = pendingVideoView {
            pendingVideoView = nil
            attachVideoView(pending)
        }
    }
}

