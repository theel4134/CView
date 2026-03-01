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
            
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            
            // Retina 디스플레이 대응 — 선명한 렌더링
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            playerLayer.contentsScale = scale
            playerLayer.magnificationFilter = .trilinear
            playerLayer.minificationFilter  = .trilinear
            
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
            // 윈도우/스크린 변경 시 contentsScale 자동 업데이트
            if let scale = window?.backingScaleFactor {
                playerLayer.contentsScale = scale
            }
        }
    }
}
