// MARK: - WindowFrameAutosave.swift
// [Persistence 2026-04-18] NSWindow 위치/크기 자동 저장 — SwiftUI WindowGroup 에 적용 가능한
// 백그라운드 NSViewRepresentable 헬퍼. AppKit 의 setFrameAutosaveName 을 활용해
// 사용자가 창을 이동/리사이즈한 직후 macOS 가 자동으로 UserDefaults 에 좌표를 저장하고
// 앱 재실행 시 동일한 위치/크기로 복원한다.

import SwiftUI
import AppKit

/// SwiftUI 뷰의 호스팅 NSWindow 를 찾아 frame autosave 이름을 설정한다.
/// 동일한 autosave 이름을 가진 창은 macOS 가 자동으로 ~/Library/Preferences 에 좌표를 저장.
struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // setFrameAutosaveName 은 같은 이름의 다른 창이 이미 사용 중이면 false 반환.
            // 그 경우에도 setFrame(frameDescriptor) 로 직접 복원 가능.
            if window.setFrameAutosaveName(name) == false {
                let key = "NSWindow Frame \(name)"
                if let saved = UserDefaults.standard.string(forKey: key) {
                    window.setFrame(from: saved)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// SwiftUI WindowGroup 의 컨텐츠에 적용하여 NSWindow 의 frame autosave 활성화.
    /// 사용 예: `.windowFrameAutosave("main-window")`
    func windowFrameAutosave(_ name: String) -> some View {
        background(WindowFrameAutosave(name: name))
    }
}
