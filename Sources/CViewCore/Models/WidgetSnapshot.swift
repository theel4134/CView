// MARK: - WidgetSnapshot.swift
// 메인 앱과 Widget Extension 사이에서 직렬화되어 교환되는 데이터 모델
//
// [Phase 1: Widget 통합 2026-04-24]
// - 메인 앱이 주기적으로 작성 → JSON 으로 App Group container 에 저장
// - Widget Extension 이 TimelineProvider 에서 읽어 표시
// - 가벼운 Codable + Sendable 구조로 유지 (CViewCore 만 의존)

import Foundation

// MARK: - WidgetLiveItem

/// 위젯에 표시할 단일 라이브 채널 항목.
///
/// `LiveChannelItem` 의 위젯 표시용 축약 버전. 위젯이 사용하지 않는 필드(`categoryType` 등)는 제외.
public struct WidgetLiveItem: Identifiable, Sendable, Codable, Equatable {
    public let id: String              // = channelId
    public let channelId: String
    public let channelName: String
    public let channelImageURL: URL?
    public let liveTitle: String
    public let viewerCount: Int
    public let categoryName: String?
    public let thumbnailURL: URL?

    public init(
        channelId: String,
        channelName: String,
        channelImageURL: URL?,
        liveTitle: String,
        viewerCount: Int,
        categoryName: String?,
        thumbnailURL: URL?
    ) {
        self.id = channelId
        self.channelId = channelId
        self.channelName = channelName
        self.channelImageURL = channelImageURL
        self.liveTitle = liveTitle
        self.viewerCount = viewerCount
        self.categoryName = categoryName
        self.thumbnailURL = thumbnailURL
    }

    /// `1.5만`, `1.2천` 같은 한국어 단위 포맷.
    public var formattedViewerCount: String {
        if viewerCount >= 10_000 {
            return String(format: "%.1f만", Double(viewerCount) / 10_000.0)
        } else if viewerCount >= 1_000 {
            return String(format: "%.1f천", Double(viewerCount) / 1_000.0)
        }
        return "\(viewerCount)"
    }
}

// MARK: - WidgetSnapshot

/// 한 번의 갱신 시점에 위젯이 표시할 모든 정보를 묶은 컨테이너.
public struct WidgetSnapshot: Sendable, Codable, Equatable {

    /// 스냅샷 직렬화 포맷 버전 (호환성 깨질 때만 증가).
    public static let currentSchemaVersion: Int = 1

    public let schemaVersion: Int
    public let generatedAt: Date

    /// 사용자가 로그인되어 있는지 여부. false 면 위젯이 "로그인 필요" placeholder 표시.
    public let isLoggedIn: Bool

    /// 팔로우 채널 중 현재 라이브인 항목 (생성 시점 기준 시청자 수 내림차순).
    public let followingLives: [WidgetLiveItem]

    /// 현재 메인 앱에서 시청 중인 라이브 (없으면 nil).
    public let nowWatching: WidgetLiveItem?

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        generatedAt: Date = Date(),
        isLoggedIn: Bool,
        followingLives: [WidgetLiveItem],
        nowWatching: WidgetLiveItem?
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.isLoggedIn = isLoggedIn
        self.followingLives = followingLives
        self.nowWatching = nowWatching
    }

    /// 위젯 placeholder/preview 용 빈 스냅샷.
    public static let empty = WidgetSnapshot(
        isLoggedIn: false,
        followingLives: [],
        nowWatching: nil
    )

    /// 위젯 preview 용 mock 스냅샷.
    public static let preview = WidgetSnapshot(
        isLoggedIn: true,
        followingLives: [
            WidgetLiveItem(
                channelId: "preview-1",
                channelName: "스트리머A",
                channelImageURL: nil,
                liveTitle: "발로란트 랭크 도전",
                viewerCount: 12_345,
                categoryName: "VALORANT",
                thumbnailURL: nil
            ),
            WidgetLiveItem(
                channelId: "preview-2",
                channelName: "스트리머B",
                channelImageURL: nil,
                liveTitle: "저녁 잡담 방송",
                viewerCount: 832,
                categoryName: "잡담",
                thumbnailURL: nil
            ),
            WidgetLiveItem(
                channelId: "preview-3",
                channelName: "스트리머C",
                channelImageURL: nil,
                liveTitle: "리그 오브 레전드",
                viewerCount: 4_521,
                categoryName: "League of Legends",
                thumbnailURL: nil
            )
        ],
        nowWatching: nil
    )

    // MARK: - Persistence (App Group)

    /// 스냅샷을 App Group container 의 widget-snapshot.json 에 atomic write.
    public func persist() throws {
        guard let url = AppGroupContainer.widgetSnapshotURL else {
            throw WidgetSnapshotError.containerUnavailable
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }

    /// App Group container 에서 스냅샷 로드. 파일 없으면 nil.
    public static func load() -> WidgetSnapshot? {
        guard let url = AppGroupContainer.widgetSnapshotURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
            // 스키마 버전 불일치 시 무시 (앱 업데이트 후 첫 갱신까지는 placeholder)
            guard snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }
}

// MARK: - Errors

public enum WidgetSnapshotError: Error, Sendable {
    case containerUnavailable
}
