// MARK: - FollowingViewState.swift
// CViewApp — 라이브 메뉴(FollowingView) 상태 보존 모델
// 다른 메뉴로 이동 후 복귀 시 상태가 초기화되지 않도록 AppState에서 관리

import SwiftUI

// MARK: - Layout Preset

enum LayoutPreset: String, CaseIterable, Identifiable {
    case chatFocus = "채팅 집중"
    case monitoring = "모니터링"
    case liveFocus = "라이브 집중"
    case chzzkWeb = "치지직 웹 크기"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chatFocus: return "bubble.left.and.bubble.right.fill"
        case .monitoring: return "rectangle.split.3x1"
        case .liveFocus: return "play.rectangle.fill"
        case .chzzkWeb: return "globe"
        }
    }
}

/// 라이브 메뉴의 영속 상태 — AppState에 보관되어 뷰 재생성에도 유지됨
@Observable
@MainActor
final class FollowingViewState {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let followingListWidth = "followingViewState.followingListWidth"
        static let dualPanelSplitRatio = "followingViewState.dualPanelSplitRatio"
        static let hideFollowingList = "followingViewState.hideFollowingList"
    }

    // MARK: - Defaults

    static let defaultFollowingListWidth: CGFloat = 480
    static let defaultDualPanelSplitRatio: CGFloat = 0.70
    /// 치지직 웹 채팅 패널 참조 너비 (웹 기준 ~300px)
    static let chzzkWebChatWidth: CGFloat = 300

    // MARK: - 정렬/필터

    var sortOrder: FollowingSortOrder = .liveFirst
    var filterLiveOnly: Bool = false
    var selectedCategory: String? = nil

    // MARK: - 페이징

    var livePageIndex: Int = 0
    var offlinePageIndex: Int = 0

    // MARK: - 멀티라이브 UI

    var showMultiLive: Bool = true
    var showMLSettings: Bool = false
    var showMultiChat: Bool = true

    /// PiP 모드 활성 여부 (비영속 — 멀티라이브 → PiP 자동 전환 시 true)
    var isMultiLivePiPMode: Bool = false
    var hideFollowingList: Bool = true {
        didSet { UserDefaults.standard.set(hideFollowingList, forKey: Keys.hideFollowingList) }
    }
    var followingListWidth: CGFloat = 480 {
        didSet { debounceSave(key: Keys.followingListWidth, value: Double(followingListWidth)) }
    }

    // MARK: - 멀티채팅
    let chatSessionManager = MultiChatSessionManager()
    var showChatAddChannel: Bool = false
    var showChatSettings: Bool = false

    /// 현재 사이드 패널 너비 (레이아웃 프리셋 계산용, 저장 안 함)
    var currentSidePanelWidth: CGFloat = 0

    // MARK: - 듀얼 패널 분할

    var dualPanelSplitRatio: CGFloat = 0.70 {
        didSet { debounceSave(key: Keys.dualPanelSplitRatio, value: Double(dualPanelSplitRatio)) }
    }

    // MARK: - Init (UserDefaults 복원)

    /// UserDefaults 디바운스 저장용 태스크 풀
    private var _saveTasks: [String: Task<Void, Never>] = [:]

    /// UserDefaults 동기 쓰기를 200ms 디바운스하여 드래그 중 디스크 I/O 최소화
    private func debounceSave(key: String, value: Double) {
        _saveTasks[key]?.cancel()
        _saveTasks[key] = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    init() {
        let ud = UserDefaults.standard
        if ud.object(forKey: Keys.followingListWidth) != nil {
            followingListWidth = CGFloat(ud.double(forKey: Keys.followingListWidth))
        }
        if ud.object(forKey: Keys.dualPanelSplitRatio) != nil {
            let stored = CGFloat(ud.double(forKey: Keys.dualPanelSplitRatio))
            // 저장값이 새 최대치(0.80)를 초과하면 기본값으로 보정
            dualPanelSplitRatio = stored > 0.80 ? Self.defaultDualPanelSplitRatio : stored
        }
        if ud.object(forKey: Keys.hideFollowingList) != nil {
            hideFollowingList = ud.bool(forKey: Keys.hideFollowingList)
        }
    }

    // MARK: - Layout Presets

    func applyPreset(_ preset: LayoutPreset) {
        switch preset {
        case .chatFocus:
            hideFollowingList = true
            showMultiChat = true
            dualPanelSplitRatio = 0.35
        case .monitoring:
            hideFollowingList = false
            followingListWidth = 300
            dualPanelSplitRatio = 0.50
        case .liveFocus:
            hideFollowingList = true
            showMultiLive = true
            dualPanelSplitRatio = 0.65
        case .chzzkWeb:
            // 치지직 웹 채팅방 크기(~300pt)에 맞춰 동적 비율 계산
            hideFollowingList = true
            showMultiChat = true
            if showMultiLive {
                let panelW = currentSidePanelWidth > 0 ? currentSidePanelWidth : 1200
                let targetRatio = 1 - (Self.chzzkWebChatWidth / panelW)
                dualPanelSplitRatio = max(0.25, min(targetRatio, 0.80))
            }
        }
    }
}
