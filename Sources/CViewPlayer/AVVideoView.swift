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
            layer?.addSublayer(playerLayer)
        }
        
        func setPlayer(_ player: AVPlayer?) {
            if playerLayer.player !== player {
                playerLayer.player = player
            }
        }
        
        override public func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
