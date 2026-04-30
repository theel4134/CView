// MARK: - CViewCore/Models/ViewState.swift
// 비동기 데이터 로딩 상태를 표준화한 enum
// docs/design-improvement-plan-2026-04.md §11 / Phase 6 참조
//
// 사용 예시:
// ```swift
// @State private var state: ViewState<[LiveInfo]> = .idle
//
// var body: some View {
//     switch state {
//     case .idle, .loading:
//         ProgressView()
//     case .loaded(let items) where items.isEmpty:
//         EmptyStateView(icon: "tv.slash", title: "데이터 없음", style: .panel)
//     case .loaded(let items):
//         List(items) { ... }
//     case .failed(let error):
//         ErrorRecoveryView(error: error) { await reload() }
//     }
// }
// ```
//
// 신규 화면부터 채택, 기존은 점진 마이그레이션.

import Foundation

/// 비동기 데이터 로딩의 4가지 표준 상태.
public enum ViewState<Value: Sendable>: Sendable {
    /// 초기 상태 — 아직 요청을 시작하지 않음.
    case idle
    /// 로딩 중 — 진행률(0.0~1.0)을 옵션으로 전달 가능.
    case loading(progress: Double? = nil)
    /// 성공 — 결과 값을 보유.
    case loaded(Value)
    /// 실패 — 에러 + 재시도 가능 여부.
    case failed(Error)

    public var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    public var error: Error? {
        if case .failed(let e) = self { return e }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension ViewState: Equatable where Value: Equatable {
    public static func == (lhs: ViewState<Value>, rhs: ViewState<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading(let a), .loading(let b)):
            return a == b
        case (.loaded(let a), .loaded(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return (a as NSError) == (b as NSError)
        default:
            return false
        }
    }
}
