// MARK: - AVPlayerLayerView.swift
// CViewPlayer - AVPlayerLayer를 소유하는 경량 NSView (GPU 렌더링 최적화)

import Foundation
import AVFoundation
import AppKit
import CoreVideo
import QuartzCore

// MARK: - GPU Render Tier (멀티라이브 compositor 스케일 제어)

/// AVPlayerLayer 의 compositor 렌더 계층.
/// `SessionTier` 와 의미가 동일하나 CViewPlayer 모듈 내부에서 순환 의존 없이 사용하도록 분리.
public enum AVGPURenderTier: Int, Sendable {
    case active  = 0
    case visible = 1
    case hidden  = 2
}

// MARK: - Video Rendering View

/// AVPlayerLayer를 소유하는 경량 NSView.
/// PlayerContainerView가 이 view를 subview로 추가하는 게 아니라
/// playerLayer를 직접 sublayer로 삽입하여 GPU compositing 레이어 1개 감소.
/// - 이 NSView 자체는 화면에 표시되지 않으므로 drawRect/redraw 완전 차단.
final class AVPlayerLayerView: NSView, @unchecked Sendable {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // backing store 생성은 하지만 화면 그리기에 관여하지 않음
        wantsLayer = true
        layer = playerLayer
        layerContentsRedrawPolicy = .never  // NSView drawRect 코드패스 완전 제거

        playerLayer.videoGravity   = .resizeAspect
        playerLayer.drawsAsynchronously = true // Metal async 렌더링 (GPU thread)
        playerLayer.isOpaque       = true      // 알파 블렌딩 없음 → GPU 부하 감소
        playerLayer.shouldRasterize = false    // 매 프레임 변경되므로 캐시 불필요
        playerLayer.allowsGroupOpacity = false // compositing group pass 제거

        // Retina 디스플레이 대응 — contentsScale을 backingScaleFactor에 맞춤
        // 미설정 시 1x로 렌더링 후 2x로 업스케일되어 흐릿해짐
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        playerLayer.contentsScale = scale
        
        // 비디오 원본 픽셀을 최대한 보존하는 필터링
        // .linear: 비디오 스케일링 시 픽셀 보간이 자연스러우면서 선명도 유지
        // .trilinear은 mipmap 기반이라 약간의 블러 발생 가능
        playerLayer.magnificationFilter = .linear
        playerLayer.minificationFilter  = .trilinear

        // ── Metal Zero-Copy 렌더링 파이프라인 ──────────────────────────────
        // pixelBufferAttributes 설정으로 VideoToolbox → Metal IOSurface 직통 경로 활성화
        // CPU 복사 없이 GPU에서 직접 디코딩→렌더링 (macOS Apple Silicon 최적)
        // FullRange(0-255)로 변경 — VideoRange(16-235)보다 색 범위가 넓어
        // VLC와 동등한 명암비/색감 표현 (대부분의 웹 HLS 스트림이 Full Range 사용)
        playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            // [Phase 4] 1080p 60fps 디코더 출력 해상도 힌트
            // VideoToolbox 하드웨어 디코더가 1920×1080 출력을 기본으로 할당
            // → 디코더 내부 스케일링 없이 원본 해상도 그대로 출력하여 선명도 극대화
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080,
        ]

        // EDR(Extended Dynamic Range) 활성화 — macOS는 EDR 지원 디스플레이에서
        // SDR 콘텐츠도 더 넓은 휘도 범위로 렌더링 가능. VLC는 자체 렌더러가 이를 자동 처리.
        playerLayer.wantsExtendedDynamicRangeContent = true

        // [Phase 4] 색 공간 최적화 — Wide Color (P3/BT.709) 콘텐츠 지원
        // RGBAF16 포맷으로 HDR/Wide Color 콘텐츠의 색상 정확도 향상
        // 일반 SDR 콘텐츠에서도 색 양자화(banding) 감소 효과
        playerLayer.contentsFormat = .RGBA16Float

        // edge 안티앨리어싱 비활성 — 비디오 프레임 경계 렌더링 비용 제거
        playerLayer.allowsEdgeAntialiasing = false

        // 이 레이어의 모든 암묵적 애니메이션 비활성화
        playerLayer.actions = [
            "position":   NSNull(),
            "bounds":     NSNull(),
            "frame":      NSNull(),
            "contents":   NSNull(),
            "opacity":    NSNull(),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(player: AVPlayer) {
        playerLayer.player = player
    }

    /// 현재 적용된 GPU 렌더 계층 (기본 full = Retina 원본)
    private var gpuRenderTier: AVGPURenderTier = .active

    /// 멀티라이브 GPU 렌더 계층에 따라 `contentsScale` 과 `isHidden` 을 조정한다.
    /// AVPlayerLayer 의 `contentsScale` 은 비디오 프레임 합성 시 출력 샘플 밀도에 영향을 주며,
    /// 낮출수록 GPU 합성 픽셀 수가 줄어든다. (디코딩 해상도와는 독립)
    ///
    /// - `.active`  : 풀 백킹 스케일 (Retina 원본)
    /// - `.visible` : 백킹 × 0.75 (약 44% 픽셀 감소)
    /// - `.hidden`  : 레이어 숨김 (합성 패스 생략)
    func setGPURenderTier(_ tier: AVGPURenderTier) {
        gpuRenderTier = tier
        applyGPURenderTier()
    }

    private func applyGPURenderTier() {
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let targetScale: CGFloat
        let shouldHide: Bool
        switch gpuRenderTier {
        case .active:
            targetScale = backing
            shouldHide = false
        case .visible:
            targetScale = max(1.0, backing * 0.75)
            shouldHide = false
        case .hidden:
            targetScale = backing
            shouldHide = true
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.isHidden = shouldHide
        playerLayer.contentsScale = targetScale
        CATransaction.commit()
    }

    /// 선명한 화면(픽셀 샤프 스케일링) 토글.
    /// - true: magnificationFilter/minificationFilter = .nearest → 픽셀 경계 유지 (에지 선명, 계단감 가능)
    /// - false: 기본 .linear / .trilinear (부드러운 보간)
    func setSharpScaling(_ enabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.magnificationFilter = enabled ? .nearest : .linear
        playerLayer.minificationFilter  = enabled ? .nearest : .trilinear
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 윈도우 이동/스크린 변경 시 tier 기반 contentsScale 재적용
        applyGPURenderTier()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Retina ↔ 일반 디스플레이 전환 시 tier 기반 contentsScale 재적용
        applyGPURenderTier()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
