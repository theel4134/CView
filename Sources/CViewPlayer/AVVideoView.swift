// MARK: - AVVideoView.swift
// CViewPlayer - AVPlayer Video NSViewRepresentable for SwiftUI
// AVPlayerLayer 기반 네이티브 비디오 렌더링

import SwiftUI
import AppKit
import AVFoundation

// MARK: - AVPlayer Video View (SwiftUI)

/// AVPlayer의 AVPlayerLayer를 NSView에 바인딩하는 SwiftUI 래퍼.
/// AVPlayerEngine의 player 인스턴스를 받아 비디오를 렌더링합니다.
public struct AVVideoView: NSViewRepresentable {
    
    private let playerEngine: AVPlayerEngine?
    
    public init(playerEngine: AVPlayerEngine?) {
        self.playerEngine = playerEngine
    }
    
    public func makeNSView(context: Context) -> AVVideoNSView {
        let view = AVVideoNSView()
        return view
    }
    
    public func updateNSView(_ nsView: AVVideoNSView, context: Context) {
        if let engine = playerEngine {
            nsView.setPlayer(engine.player)
        } else {
            nsView.setPlayer(nil)
        }
    }
    
    /// AVPlayerLayer를 사용하는 커스텀 NSView
    public final class AVVideoNSView: NSView {
        
        private let playerLayer: AVPlayerLayer
        
        override public var isFlipped: Bool { true }
        
        override public init(frame frameRect: NSRect) {
            self.playerLayer = AVPlayerLayer()
            super.init(frame: frameRect)
            commonInit()
        }
        
        required init?(coder: NSCoder) {
            self.playerLayer = AVPlayerLayer()
            super.init(coder: coder)
            commonInit()
        }
        
        private func commonInit() {
            wantsLayer = true
            layerContentsRedrawPolicy = .never       // drawRect 차단 — 리사이즈 시 불필요한 redraw 방지
            
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            
            // Retina 디스플레이 대응 — 선명한 렌더링
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            playerLayer.contentsScale = scale
            
            // .linear: 비디오 스케일링 시 픽셀 보간이 자연스러우면서 선명도 유지
            playerLayer.magnificationFilter = .linear
            playerLayer.minificationFilter  = .trilinear
            
            // Metal Zero-Copy 렌더링 파이프라인
            // FullRange(0-255): VideoRange(16-235)보다 색 범위가 넓어 VLC 동등 명암비/색감
            playerLayer.pixelBufferAttributes = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            
            // GPU 최적화
            playerLayer.drawsAsynchronously = true
            playerLayer.isOpaque = true
            playerLayer.allowsGroupOpacity = false
            playerLayer.shouldRasterize = false
            playerLayer.allowsEdgeAntialiasing = false
            
            // HDR/Wide Color 지원
            playerLayer.wantsExtendedDynamicRangeContent = true
            
            // 암묵적 애니메이션 비활성화
            playerLayer.actions = [
                "position": NSNull(), "bounds": NSNull(),
                "frame": NSNull(), "contents": NSNull(),
            ]
            
            layer?.addSublayer(playerLayer)
        }
        
        func setPlayer(_ player: AVPlayer?) {
            if playerLayer.player !== player {
                playerLayer.player = player
            }
        }

        /// 비디오 화면 채움 모드 변경 (true: aspect-fill, false: aspect-fit 레터박스)
        func setFillMode(_ fill: Bool) {
            playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        }
        
        override public func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
        
        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scale = window?.backingScaleFactor {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.contentsScale = scale
                CATransaction.commit()
            }
        }

        override public func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            // Retina ↔ 일반 디스플레이 전환 시 즉시 반영
            if let scale = window?.backingScaleFactor {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.contentsScale = scale
                CATransaction.commit()
            }
        }
    }
}
