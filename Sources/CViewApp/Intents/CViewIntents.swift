// MARK: - CViewIntents.swift
// App Intents — Shortcuts/Spotlight/Siri 진입점.
//
// 설계 원칙:
//   - 모든 인텐트는 `cview://` URL 을 만들어 NSWorkspace 로 앱을 깨운다.
//   - 앱은 `.onOpenURL` → `DeepLinkRouter.handle(...)` → `CViewActionRegistry.dispatch(...)` 로 위임.
//   - 결과적으로 모든 진입점(CommandPalette/DeepLink/Widget/AppIntent)이 동일한 액션 enum 을 공유.
//
// [Plan 2026-04-30 ACT-3]

import AppIntents
import Foundation
import AppKit

// MARK: - Intent Enums (App Intents 노출용)

enum CViewLiveOpenModeIntent: String, AppEnum {
    case watch
    case multi
    case chatOnly

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "라이브 진입 모드")
    }

    static let caseDisplayRepresentations: [CViewLiveOpenModeIntent: DisplayRepresentation] = [
        .watch:    DisplayRepresentation(title: "단일 시청"),
        .multi:    DisplayRepresentation(title: "멀티라이브 추가"),
        .chatOnly: DisplayRepresentation(title: "채팅만 열기"),
    ]

    var urlValue: String {
        switch self {
        case .watch:    "watch"
        case .multi:    "multi"
        case .chatOnly: "chatonly"
        }
    }
}

enum CViewFollowingHubModeIntent: String, AppEnum {
    case explore
    case watch
    case multi

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "라이브 메뉴 모드")
    }

    static let caseDisplayRepresentations: [CViewFollowingHubModeIntent: DisplayRepresentation] = [
        .explore: DisplayRepresentation(title: "탐색"),
        .watch:   DisplayRepresentation(title: "시청"),
        .multi:   DisplayRepresentation(title: "멀티"),
    ]

    var urlValue: String { rawValue }
}

enum CViewMetricsTabIntent: String, AppEnum {
    case overview
    case channels
    case monitoring

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "메트릭 탭")
    }

    static let caseDisplayRepresentations: [CViewMetricsTabIntent: DisplayRepresentation] = [
        .overview:   DisplayRepresentation(title: "개요"),
        .channels:   DisplayRepresentation(title: "채널"),
        .monitoring: DisplayRepresentation(title: "모니터링"),
    ]

    var urlValue: String { rawValue }
}

// MARK: - Helper

private enum CViewIntentBridge {
    /// `cview://` URL 을 만들고 시스템에 열기를 요청.
    @MainActor
    static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Intents

struct OpenLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "라이브 시청"
    static let description = IntentDescription("채널 ID로 라이브 시청 화면을 엽니다.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "채널 ID")
    var channelId: String

    @Parameter(title: "모드", default: .watch)
    var mode: CViewLiveOpenModeIntent

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .result()
        }
        CViewIntentBridge.openURL("cview://live?channelId=\(encoded)&mode=\(mode.urlValue)")
        return .result()
    }
}

struct AddToMultiLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "멀티라이브에 추가"
    static let description = IntentDescription("채널을 멀티라이브 세션에 추가합니다.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "채널 ID")
    var channelId: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .result()
        }
        CViewIntentBridge.openURL("cview://live?channelId=\(encoded)&mode=multi")
        return .result()
    }
}

struct SwitchLiveModeIntent: AppIntent {
    static let title: LocalizedStringResource = "라이브 메뉴 모드 전환"
    static let description = IntentDescription("라이브 메뉴를 탐색/시청/멀티 중 하나로 전환합니다.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "모드", default: .watch)
    var mode: CViewFollowingHubModeIntent

    @MainActor
    func perform() async throws -> some IntentResult {
        CViewIntentBridge.openURL("cview://following?mode=\(mode.urlValue)")
        return .result()
    }
}

struct OpenMetricsIntent: AppIntent {
    static let title: LocalizedStringResource = "메트릭 대시보드 열기"
    static let description = IntentDescription("메트릭 대시보드를 엽니다. 탭을 지정할 수 있습니다.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "탭", default: .overview)
    var tab: CViewMetricsTabIntent

    @MainActor
    func perform() async throws -> some IntentResult {
        CViewIntentBridge.openURL("cview://metrics?tab=\(tab.urlValue)")
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct CViewAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLiveIntent(),
            phrases: ["\(.applicationName)에서 라이브 보기"],
            shortTitle: "라이브 시청",
            systemImageName: "play.tv.fill"
        )
        AppShortcut(
            intent: AddToMultiLiveIntent(),
            phrases: ["\(.applicationName) 멀티라이브에 추가"],
            shortTitle: "멀티라이브 추가",
            systemImageName: "rectangle.3.group.fill"
        )
        AppShortcut(
            intent: SwitchLiveModeIntent(),
            phrases: ["\(.applicationName) 라이브 모드 전환"],
            shortTitle: "라이브 모드",
            systemImageName: "rectangle.split.3x1"
        )
        AppShortcut(
            intent: OpenMetricsIntent(),
            phrases: ["\(.applicationName) 메트릭 보기"],
            shortTitle: "메트릭",
            systemImageName: "chart.bar.xaxis"
        )
    }
}
