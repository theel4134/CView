// MARK: - NowWatchingWidget.swift
// 현재 본 앱에서 시청 중인 라이브 표시 (S/M).

import WidgetKit
import SwiftUI
import CViewCore

struct NowWatchingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview)
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshotLoader.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotLoader.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
}

struct NowWatchingWidget: Widget {
    let kind = "NowWatchingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowWatchingProvider()) { entry in
            NowWatchingView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("시청 중")
        .description("CView 에서 현재 시청 중인 라이브를 표시합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NowWatchingView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry

    var body: some View {
        if let item = entry.snapshot.nowWatching {
            Link(destination: WidgetDeepLink.live(channelId: item.channelId)) {
                if family == .systemSmall {
                    smallBody(item)
                } else {
                    mediumBody(item)
                }
            }
        } else {
            EmptyPlaceholder(message: "지금 시청 중인 라이브가 없습니다.")
        }
    }

    private func smallBody(_ item: WidgetLiveItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("LIVE").font(.caption2.bold()).foregroundStyle(.red)
                Spacer()
            }
            RemoteImage(url: item.channelImageURL)
                .frame(width: 32, height: 32).clipShape(Circle())
            Text(item.channelName).font(.caption.bold()).lineLimit(1)
            Text(item.liveTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private func mediumBody(_ item: WidgetLiveItem) -> some View {
        HStack(spacing: 10) {
            RemoteImage(url: item.thumbnailURL ?? item.channelImageURL)
                .frame(width: 96, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("시청 중").font(.caption2.bold()).foregroundStyle(.red)
                }
                Text(item.channelName).font(.caption.bold()).lineLimit(1)
                Text(item.liveTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Text(item.formattedViewerCount + " 명").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
