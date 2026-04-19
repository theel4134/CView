// MARK: - ChildWindowChromeApplier.swift
// 멀티라이브 자식 인스턴스에서, SwiftUI WindowGroup 가 창을 띄우는 즉시
// borderless / 위치 / Dock 정책을 적용하기 위한 헬퍼.
//
// 기존에는 SwiftUI .onAppear 에서 적용했지만 그 시점은 창이 이미 화면에 그려진 후라
// 부모 앱과 분리된 풀-크롬 창이 잠시 보이는 문제가 있었다.
// NSWindow.didBecomeKey / didBecomeMain 을 한 번 가로채서 첫 창에 즉시 적용.

import AppKit
import Foundation

@MainActor
enum ChildWindowChromeApplier {
    private static var token: NSObjectProtocol?

    static func install(config: MultiLiveChildConfig) {
        // 이미 설치돼 있으면 무시
        if token != nil { return }

        let center = NotificationCenter.default
        // didBecomeKey 가 첫 창 표시 직후 가장 빠르게 fire 되는 노티 중 하나
        token = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let win = note.object as? NSWindow else { return }
            apply(to: win, config: config)
            // 한 번만 적용
            if let t = token {
                NotificationCenter.default.removeObserver(t)
                token = nil
            }
        }

        // didBecomeKey 가 늦게 오는 케이스 대비: NSApp.windows 폴링 (최대 1초)
        Task { @MainActor in
            for _ in 0..<20 {
                if let win = NSApp.windows.first(where: { $0.isVisible }) {
                    apply(to: win, config: config)
                    if let t = token {
                        NotificationCenter.default.removeObserver(t)
                        token = nil
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private static func apply(to win: NSWindow, config: MultiLiveChildConfig) {
        if config.borderless {
            // 보더리스 + 부모 영역에 정렬
            win.styleMask = [.borderless, .resizable]
            win.isMovableByWindowBackground = false
            win.hasShadow = false
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.standardWindowButton(.closeButton)?.isHidden = true
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
            win.level = .floating
            win.collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            win.title = "CView – \(config.channelName)"
        }
        if let frame = config.initialFrame {
            win.setFrame(frame, display: true)
        }
    }
}
