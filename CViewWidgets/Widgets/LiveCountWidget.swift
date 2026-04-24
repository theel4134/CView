// MARK: - LiveCountWidget.swift
// 팔로우 채널 중 라이브 채널 수 카운트 (S).

import WidgetKit
import SwiftUI
import CViewCore

struct LiveCountProvider: TimelineProvider {
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

struct LiveCountWidget: Widget {
    let kind = "LiveCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiveCountProvider()) { entry in
            LiveCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("라이브 카운트")
        .description("팔로우 채널 중 현재 라이브 중인 수를 표시합니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct LiveCountView: View {
    let entry: SnapshotEntry

    var body: some View {
        Link(destination: WidgetDeepLink.following) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("LIVE").font(.caption2.bold()).foregroundStyle(.red)
                    Spacer()
                }
                Spacer(minLength: 0)
                Text("\(entry.snapshot.followingLives.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("팔로잉 라이브")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
