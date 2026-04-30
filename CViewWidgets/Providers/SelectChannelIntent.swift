// MARK: - SelectChannelIntent.swift
// SingleChannelWidget 의 채널 선택용 AppIntent.
// 위젯 편집 모드에서 "채널 선택" 드롭다운으로 노출됨.

import AppIntents
import CViewCore

struct SelectChannelIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "채널 선택"
    static let description = IntentDescription("위젯에 표시할 단일 채널을 선택합니다.")

    @Parameter(title: "채널")
    var channel: WidgetChannelEntity?

    init() {}
    init(channel: WidgetChannelEntity?) {
        self.channel = channel
    }
}

/// 위젯 채널 선택을 위한 AppEntity. App Group 캐시(팔로잉 목록)에서 enumerate 한다.
struct WidgetChannelEntity: AppEntity, Identifiable, Hashable {
    var id: String
    var displayName: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "채널"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    static let defaultQuery = WidgetChannelQuery()
}

struct WidgetChannelQuery: EntityQuery {
    func entities(for identifiers: [WidgetChannelEntity.ID]) async throws -> [WidgetChannelEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetChannelEntity] {
        let snapshot = WidgetSnapshot.load() ?? .empty
        return snapshot.followingLives.map {
            WidgetChannelEntity(id: $0.channelId, displayName: $0.channelName)
        }
    }

    func defaultResult() async -> WidgetChannelEntity? {
        (try? await suggestedEntities())?.first
    }
}
