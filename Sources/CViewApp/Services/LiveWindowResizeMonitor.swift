// MARK: - LiveWindowResizeMonitor.swift
// 앱 어느 NSWindow 든 라이브 리사이즈(가장자리 드래그) 중인지 추적.
//
// 배경:
// ──────────────────────────────────────────────────────────────────────────
// 루트 WindowGroup 의 `.transaction { t in if t.animation == nil { t.animation = ... } }`
// 는 모든 암묵적 상태 변화에 spring 애니메이션을 강제 부여한다. 이 때문에
// 사용자가 창을 드래그/리사이즈하는 동안 SwiftUI 레이아웃 패스 갱신마다
// 추가 애니메이션 보간이 발생하여 프레임이 끊겨 보이는 문제를 유발.
//
// 본 모니터는 NSWindow.willStartLiveResize / didEndLiveResize 노티를 관찰하여
// 활성 라이브 리사이즈 카운트를 유지한다. 글로벌 transaction modifier 가
// `isAnyWindowLiveResizing == true` 인 동안엔 애니메이션 주입을 건너뛰어
// 레이아웃이 즉시 반영되도록 한다.
//
// 비용: 노티 두 종 + Int 카운터. CPU/메모리 영향 사실상 0.
//
// 호출 시점: CViewApp.body 의 onAppear 에서 한 번 install().

import AppKit
import Foundation

@MainActor
enum LiveWindowResizeMonitor {

    /// 현재 어떤 NSWindow 든 라이브 리사이즈 중이면 true.
    /// 글로벌 .transaction 이 애니메이션 주입 여부를 결정할 때 참조.
    private(set) static var isAnyWindowLiveResizing: Bool = false

    private static var liveResizeCount: Int = 0
    private static var installed: Bool = false
    private static var tokens: [NSObjectProtocol] = []

    /// 앱 시작 시 한 번 호출. 멱등.
    static func install() {
        guard !installed else { return }
        installed = true

        let center = NotificationCenter.default

        let startToken = center.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 메인 큐 콜백이지만 isolation 보장을 위해 MainActor.assumeIsolated 로 감쌈
            MainActor.assumeIsolated {
                liveResizeCount += 1
                isAnyWindowLiveResizing = true
            }
        }

        let endToken = center.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                liveResizeCount = max(0, liveResizeCount - 1)
                if liveResizeCount == 0 {
                    isAnyWindowLiveResizing = false
                }
            }
        }

        tokens = [startToken, endToken]
    }
}
