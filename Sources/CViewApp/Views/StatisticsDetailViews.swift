// MARK: - StatisticsDetailViews.swift
// CViewApp - 통계 상세 뷰 (StreamingStats, ChatStats, WatchHistory, StatCard)
// StatisticsView.swift에서 분리

import SwiftUI
import Charts
import CViewCore
import CViewMonitoring
import CViewPersistence
import CViewUI
import CViewChat

// MARK: - Streaming Stats

struct StreamingStatsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                statsSection("스트리밍 품질", icon: "waveform", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "지연 시간",
                            value: appState.playerViewModel?.formattedLatency ?? "-",
                            icon: "clock.arrow.2.circlepath",
                            color: .green
                        )
                        StatCard(
                            title: "버퍼 상태",
                            value: appState.playerViewModel?.bufferHealth?.isHealthy == true ? "정상" : "부족",
                            icon: "chart.bar.fill",
                            color: appState.playerViewModel?.bufferHealth?.isHealthy == true ? .green : .red
                        )
                        StatCard(
                            title: "재생 속도",
                            value: appState.playerViewModel?.formattedPlaybackRate ?? "1.0x",
                            icon: "speedometer",
                            color: .orange
                        )
                    }
                }
                
                // MARK: - Latency Chart
                if let history = appState.playerViewModel?.latencyHistory, history.count >= 2 {
                    statsSection("레이턴시 추이", icon: "chart.xyaxis.line", color: latencyChartColor) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            // Current value badge
                            if let current = appState.playerViewModel?.latencyInfo?.current {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(latencyColor(for: current))
                                        .frame(width: 8, height: 8)
                                    Text(String(format: "현재 %.1f초", current))
                                        .font(DesignTokens.Typography.custom(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(latencyColor(for: current))
                                }
                            }
                            
                            Chart(history) { point in
                                AreaMark(
                                    x: .value("시간", point.timestamp),
                                    y: .value("레이턴시", point.latency)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [latencyChartColor.opacity(0.3), latencyChartColor.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                
                                LineMark(
                                    x: .value("시간", point.timestamp),
                                    y: .value("레이턴시", point.latency)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(latencyChartColor)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                            .chartYAxisLabel("레이턴시 (초)")
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                        .foregroundStyle(DesignTokens.Colors.border.opacity(0.3))
                                    AxisValueLabel()
                                        .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                            }
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                        .foregroundStyle(DesignTokens.Colors.border.opacity(0.2))
                                    AxisValueLabel(format: .dateTime.minute().second())
                                        .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                            }
                            .chartPlotStyle { plot in
                                plot.background(Color.clear)
                            }
                            .frame(height: 180)
                            
                            // Threshold legend
                            HStack(spacing: DesignTokens.Spacing.md) {
                                legendDot(color: .green, label: "< 3초")
                                legendDot(color: .yellow, label: "3-5초")
                                legendDot(color: .red, label: "> 5초")
                            }
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .padding(DesignTokens.Spacing.sm)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
                        }
                    }
                }
                
                statsSection("화질 정보", icon: "sparkles.tv", color: DesignTokens.Colors.accentBlue) {
                    if let qualities = appState.playerViewModel?.availableQualities, !qualities.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(qualities) { q in
                                HStack {
                                    Text(q.name)
                                        .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    Spacer()
                                    if q.id == appState.playerViewModel?.currentQuality?.id {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(DesignTokens.Colors.chzzkGreen)
                                                .frame(width: 6, height: 6)
                                            Text("현재")
                                                .font(DesignTokens.Typography.captionMedium)
                                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                        }
                                    }
                                }
                                .padding(DesignTokens.Spacing.sm)
                                .background(
                                    q.id == appState.playerViewModel?.currentQuality?.id
                                        ? DesignTokens.Colors.chzzkGreen.opacity(0.08)
                                        : DesignTokens.Colors.surfaceBase
                                )
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                            }
                        }
                    } else {
                        Text("화질 정보 없음")
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .padding()
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.background)
    }
    
    private func statsSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            content()
        }
    }
    
    // MARK: - Latency Chart Helpers
    
    private var latencyChartColor: Color {
        guard let current = appState.playerViewModel?.latencyInfo?.current else { return .green }
        return latencyColor(for: current)
    }
    
    private func latencyColor(for value: Double) -> Color {
        if value < 3 { return .green }
        if value < 5 { return .yellow }
        return .red
    }
    
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }
}

// MARK: - Chat Stats

struct ChatStatsView: View {
    @Environment(AppState.self) private var appState
    
    private var chatVM: ChatViewModel? { appState.chatViewModel }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                statsSection("채팅 통계", icon: "bubble.left.fill", color: DesignTokens.Colors.accentPurple) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "총 메시지",
                            value: "\(chatVM?.messageCount ?? 0)",
                            icon: "bubble.left.fill",
                            color: .blue
                        )
                        StatCard(
                            title: "초당 메시지",
                            value: String(format: "%.1f", chatVM?.messagesPerSecond ?? 0),
                            icon: "bolt.fill",
                            color: .yellow
                        )
                        StatCard(
                            title: "연결 상태",
                            value: connectionStatusText,
                            icon: connectionIcon,
                            color: connectionColor
                        )
                    }
                }
                
                statsSection("참여 통계", icon: "person.3.fill", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "참여 유저",
                            value: "\(chatVM?.uniqueUserCount ?? 0)",
                            icon: "person.2.fill",
                            color: .cyan
                        )
                        StatCard(
                            title: "도네이션",
                            value: "\(chatVM?.donationCount ?? 0)건",
                            icon: "gift.fill",
                            color: .orange
                        )
                        StatCard(
                            title: "도네 총액",
                            value: "₩\(chatVM?.totalDonationAmount ?? 0)",
                            icon: "wonsign.circle.fill",
                            color: .red
                        )
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "구독",
                            value: "\(chatVM?.subscriptionCount ?? 0)건",
                            icon: "star.fill",
                            color: .yellow
                        )
                    }
                }
                
                statsSection("최근 메시지", icon: "text.bubble", color: DesignTokens.Colors.accentBlue) {
                    let recentMessages: [ChatMessageItem] = {
                        guard let buf = chatVM?.messages, !buf.isEmpty else { return [] }
                        return Array(buf.suffix(10).reversed())
                    }()
                    if recentMessages.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(DesignTokens.Typography.title)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("메시지 없음")
                                .font(DesignTokens.Typography.captionMedium)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(recentMessages) { msg in
                                HStack(spacing: 8) {
                                    Text(msg.nickname)
                                        .font(DesignTokens.Typography.captionSemibold)
                                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                                        .frame(width: 80, alignment: .leading)
                                        .lineLimit(1)
                                    Text(msg.content)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                            }
                        }
                        .padding(DesignTokens.Spacing.sm)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.background)
    }
    
    private var connectionStatusText: String {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected: "연결됨"
        case .connecting: "연결 중"
        case .reconnecting: "재연결"
        case .disconnected: "끊김"
        case .failed: "실패"
        }
    }
    
    private var connectionIcon: String {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected: "wifi"
        case .connecting, .reconnecting: "wifi.exclamationmark"
        case .disconnected, .failed: "wifi.slash"
        }
    }
    
    private var connectionColor: Color {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected, .failed: .red
        }
    }
    
    private func statsSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            content()
        }
    }
}

// MARK: - Watch History Stats

struct WatchHistoryStatsView: View {
    @Environment(AppState.self) private var appState

    @State private var watchHistory: [CViewPersistence.WatchHistoryData] = []
    @State private var totalWatchTime: TimeInterval = 0
    @State private var topChannels: [(channelName: String, duration: TimeInterval)] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── 총 시청 시간 요약
                statsSection("시청 요약", icon: "clock.fill", color: DesignTokens.Colors.accentOrange) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "총 시청 시간",
                            value: formattedTotalTime,
                            icon: "clock.fill",
                            color: DesignTokens.Colors.accentOrange
                        )
                        StatCard(
                            title: "시청 횟수",
                            value: "\(watchHistory.count)회",
                            icon: "play.tv.fill",
                            color: DesignTokens.Colors.accentBlue
                        )
                        StatCard(
                            title: "채널 수",
                            value: "\(uniqueChannelCount)개",
                            icon: "person.2.fill",
                            color: DesignTokens.Colors.accentPurple
                        )
                    }
                }

                // ── 채널별 시청 시간 Top5
                if !topChannels.isEmpty {
                    statsSection("채널별 시청 시간", icon: "chart.bar.fill", color: DesignTokens.Colors.accentBlue) {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(Array(topChannels.enumerated()), id: \.offset) { idx, entry in
                                channelBarRow(rank: idx + 1, name: entry.channelName, duration: entry.duration)
                            }
                        }
                    }
                }

                // ── 최근 시청 기록
                statsSection("최근 시청 기록", icon: "clock.arrow.circlepath", color: DesignTokens.Colors.accentOrange) {
                    if isLoading {
                        HStack { Spacer(); ProgressView().tint(DesignTokens.Colors.accentOrange); Spacer() }
                            .frame(minHeight: 80)
                    } else if watchHistory.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(DesignTokens.Colors.surfaceBase)
                                    .frame(width: 64, height: 64)
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(DesignTokens.Typography.title)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Text("시청 기록이 없습니다")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                            Text("라이브 방송을 시청하면 여기에 자동으로 기록됩니다")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(watchHistory.prefix(20)) { record in
                                watchHistoryRow(record)
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.background)
        .task { await loadHistory() }
        .refreshable { await loadHistory() }
    }

    // MARK: - 채널별 시청 시간 바 행

    private func channelBarRow(rank: Int, name: String, duration: TimeInterval) -> some View {
        let maxDuration = topChannels.first?.duration ?? 1
        let ratio = min(1.0, duration / maxDuration)
        return HStack(spacing: DesignTokens.Spacing.sm) {
            // 순위
            Text("\(rank)")
                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 18, alignment: .trailing)

            // 채널명
            Text(name)
                .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            // 진행 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(
                            LinearGradient(
                                colors: [DesignTokens.Colors.accentBlue.opacity(0.7), DesignTokens.Colors.accentPurple.opacity(0.9)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)

            // 시간
            Text(formatDuration(duration))
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.accentBlue)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
        }
    }

    // MARK: - 최근 시청 기록 행

    private func watchHistoryRow(_ record: CViewPersistence.WatchHistoryData) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 썸네일
            if let thumbStr = record.thumbnailURL, let url = URL(string: thumbStr) {
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 54, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            } else {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 54, height: 30)
                    .overlay {
                        Image(systemName: "play.tv")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.channelName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let cat = record.categoryName, !cat.isEmpty {
                        Text(cat)
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(record.formattedDate)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            Spacer()

            // 시청 시간
            if record.duration > 60 {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(DesignTokens.Typography.micro)
                    Text(record.formattedDuration)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.Colors.accentOrange)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.accentOrange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
        }
    }

    // MARK: - Computed

    private var formattedTotalTime: String {
        let hours = Int(totalWatchTime) / 3600
        let minutes = (Int(totalWatchTime) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)분" }
        return "0분"
    }

    private var uniqueChannelCount: Int {
        Set(watchHistory.map(\.channelId)).count
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let hours = Int(t) / 3600
        let minutes = (Int(t) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)분"
    }

    // MARK: - Data Loading

    private func loadHistory() async {
        guard let ds = appState.dataStore else { isLoading = false; return }
        isLoading = true
        watchHistory = (try? await ds.fetchWatchHistory(limit: 50)) ?? []
        totalWatchTime = (try? await ds.totalWatchTime()) ?? 0
        topChannels = (try? await ds.watchTimeByChannel(limit: 5)) ?? []
        isLoading = false
    }

    private func statsSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            content()
        }
    }
}

// MARK: - Stat Card Component (Premium)

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 10) {
            // Icon with color circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 17))
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(DesignTokens.Typography.custom(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isHovered ? color.opacity(0.3) : .white.opacity(DesignTokens.Glass.borderOpacity),
                    lineWidth: isHovered ? 1 : 0.5
                )
        }
        // Metal 3: hover scaleEffect 제거 — GPU texture scale 연산 방지
        // 바닥색+테두리 변경으로만 hover 표현
        .drawingGroup(opaque: false)  // 카드 컨텐츠 단일 Metal 텍스처
        .animation(DesignTokens.Animation.smooth, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }
}
