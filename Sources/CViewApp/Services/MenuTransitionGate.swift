// MARK: - MenuTransitionGate.swift
// 사이드바/탭 메뉴 전환 직후 일정 시간 동안 글로벌 spring transaction 주입을 차단.
//
// 배경:
// ──────────────────────────────────────────────────────────────────────────
// 루트 WindowGroup 의 `.transaction { t.animation = .spring(...) }` 은
// 모든 암묵적 상태 변화에 spring 애니메이션을 부여한다. 메뉴 전환 시점에
// detail 영역의 새 루트 뷰(HomeView_v2 / FollowingView / CategoryBrowseView ...)
// 가 마운트되면서 발생하는 수십~수백 개의 암묵적 상태 변화(레이아웃, 등장
// 트랜지션, 데이터 바인딩 초기 적용 등) 가 모두 spring(0.28) 보간을 거치며
// CPU/GPU 비용이 폭증 → 첫 프레임 드롭이 보고됨.
//
// 본 게이트는 사이드바 선택이 변경되면 활성화되어 350ms 동안 transaction
// 주입을 건너뛰게 한다. 그 시간 동안 신규 화면이 정적 첫 프레임으로 즉시
// 렌더된 뒤, 이후 사용자 인터랙션부턴 정상적으로 spring 트랜지션이 동작.
//
// 비용: Bool + Task. 메뉴 전환 시에만 1회 트리거.

import Foundation

@MainActor
enum MenuTransitionGate {

    /// true 인 동안 CViewApp 의 .transaction 모디파이어가 spring 주입을 건너뛴다.
    private(set) static var isTransitioning: Bool = false

    /// 게이트 자동 해제용 작업 핸들 (연속 전환 시 재시작 가능)
    private static var releaseTask: Task<Void, Never>?

    /// 메뉴 전환 발생 알림 — 사이드바 선택, 탭 변경 등 무거운 상태 전환 직전/직후 호출.
    /// `duration` 동안 글로벌 spring transaction 비활성화 → 신규 화면이 정적으로 즉시 렌더.
    /// 기본값 0.35s 는 NavigationSplitView detail 첫 프레임 + 후속 데이터 바인딩이 안착하는 시간.
    static func notifyMenuChange(duration: TimeInterval = 0.35) {
        isTransitioning = true
        releaseTask?.cancel()
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            isTransitioning = false
        }
    }
}
