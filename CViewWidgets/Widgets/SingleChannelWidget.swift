// MARK: - SingleChannelWidget.swift
// 사용자 선택 단일 채널 상세 (S/M). AppIntent 기반 IntentConfiguration.

import WidgetKit
import SwiftUI
import AppIntents
import CViewCore

struct SingleChannelEntry: TimelineEntry {
    let date: Date
    let item: WidgetLiveItem?
    let isLoggedIn: Bool
    let channelDisplayName: String?
}

struct SingleChannelProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleChannelEntry {
        SingleChannelEntry(
            date: Date(),
            item: WidgetSnapshot.preview.followingLives.first,
            isLoggedIn: true,
            channelDisplayName: "프리뷰 채널"
        )
    }

    func snapshot(for configuration: SelectChannelIntent, in context: Context) async -> SingleChannelEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectChannelIntent, in context: Context) async -> Timeline<SingleChannelEntry> {
        let e = entry(for: configuration)
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(300)))
    }

    private func entry(for configuration: SelectChannelIntent) -> SingleChannelEntry {
        let snapshot = WidgetSnapshotLoader.load()
        let target = configuration.channel
        let item: WidgetLiveItem? = {
            guard let target else { return snapshot.followingLives.first }
            return snapshot.followingLives.first(where: { $0.channelId == target.id })
        }()
        return SingleChannelEntry(
            date: Date(),
            item: item,
            isLoggedIn: snapshot.isLoggedIn,
            channelDisplayName: target?.displayName ?? item?.channelName
        )
    }
}

struct SingleChannelWidget: Widget {
    let kind = "SingleChannelWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectChannelIntent.self, provider: SingleChannelProvider()) { entry in
            SingleChannelView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("단일 채널")
        .description("선택한 채널의 라이브 상태를 표시합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SingleChannelView: View {
    @Environment(\.widgetFamily) var family
    let entry: SingleChannelEntry

    var body: some View {
        if !entry.isLoggedIn {
            LoggedOutPlaceholder()
        } else if let item = entry.item {
            Link(destination: WidgetDeepLink.live(channelId: item.channelId)) {
                content(for: item)
            }
        } else if let name = entry.channelDisplayName {
            offlinePlaceholder(name: name)
        } else {
            EmptyPlaceholder(message: "위젯 편집에서 채널을 선택하세요.")
        }
    }

    @ViewBuilder
    private func content(for item: WidgetLiveItem) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RemoteImage(url: item.channelImageURL)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                    Text(item.channelName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(item.liveTitle)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(item.formattedViewerCount)
                        .font(.caption2.monospacedDigit())
                }
            }
        } else {
            HStack(spacing: 10) {
                RemoteImage(url: item.thumbnailURL ?? item.channelImageURL)
                    .frame(width: 96, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.channelName).font(.caption.bold()).lineLimit(1)
                    Text(item.liveTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(item.formattedViewerCount).font(.caption2.monospacedDigit())
                        if let cat = item.categoryName, !cat.isEmpty {
                            Text("· \(cat)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func offlinePlaceholder(name: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(name).font(.caption.bold())
            Text("오프라인").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
