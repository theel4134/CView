// MARK: - FollowingLiveListWidget.swift
// 팔로우 라이브 목록 (M/L/XL).

import WidgetKit
import SwiftUI
import CViewCore

struct FollowingLiveListProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : WidgetSnapshotLoader.load()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotLoader.load())
        let next = Date().addingTimeInterval(300)  // 5분 후 갱신
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FollowingLiveListWidget: Widget {
    let kind = "FollowingLiveListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FollowingLiveListProvider()) { entry in
            FollowingLiveListView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("팔로잉 라이브")
        .description("팔로우한 채널 중 라이브 중인 목록을 표시합니다.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct FollowingLiveListView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry

    private var maxItems: Int {
        switch family {
        case .systemMedium: return 2
        case .systemLarge: return 4
        case .systemExtraLarge: return 6
        default: return 2
        }
    }

    var body: some View {
        if !entry.snapshot.isLoggedIn {
            LoggedOutPlaceholder()
        } else if entry.snapshot.followingLives.isEmpty {
            EmptyPlaceholder(message: "현재 라이브 중인 팔로우 채널이 없습니다.")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("팔로잉 라이브")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.snapshot.ageDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entry.snapshot.followingLives.prefix(maxItems), id: \.channelId) { item in
                    Link(destination: WidgetDeepLink.live(channelId: item.channelId)) {
                        LiveItemRow(item: item)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LiveItemRow: View {
    let item: WidgetLiveItem

    var body: some View {
        HStack(spacing: 8) {
            RemoteImage(url: item.channelImageURL)
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.channelName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(item.liveTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(item.formattedViewerCount)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LoggedOutPlaceholder: View {
    var body: some View {
        Link(destination: WidgetDeepLink.home) {
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("CView 에서 로그인이 필요합니다")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct EmptyPlaceholder: View {
    let message: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "moon.zzz")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
