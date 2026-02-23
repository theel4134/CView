// MARK: - StatisticsView.swift
// CViewApp - 프리미엄 통계/분석 대시보드
// Design: 모던 대시보드 + 그라데이션 카드

import SwiftUI
import CViewCore
import CViewMonitoring
import CViewPersistence
import CViewUI
import CViewChat

/// 스트리밍 통계 대시보드
struct StatisticsView: View {
    
    @Environment(AppState.self) private var appState
    @State private var selectedTab: StatTab = .session
    
    enum StatTab: String, CaseIterable, Identifiable {
        case session = "세션"
        case streaming = "스트리밍"
        case chat = "채팅"
        case history = "기록"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .session: "clock"
            case .streaming: "waveform"
            case .chat: "bubble.left.and.bubble.right"
            case .history: "calendar"
            }
        }
        
        var color: Color {
            switch self {
            case .session: DesignTokens.Colors.accentBlue
            case .streaming: DesignTokens.Colors.chzzkGreen
            case .chat: DesignTokens.Colors.accentPurple
            case .history: DesignTokens.Colors.accentOrange
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Stats header
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("통계")
                        .font(.system(size: 14, weight: .bold))
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                
                List(StatTab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(selectedTab == tab ? tab.color : DesignTokens.Colors.textSecondary)
                            .frame(width: 20)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 150)
            .background(DesignTokens.Colors.backgroundDark)
        } detail: {
            tabContent
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .session:
            SessionStatsView()
        case .streaming:
            StreamingStatsView()
        case .chat:
            ChatStatsView()
        case .history:
            WatchHistoryStatsView()
        }
    }
}

// MARK: - Session Stats

struct SessionStatsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Session Overview
                statsSection("세션 개요", icon: "clock.fill", color: DesignTokens.Colors.accentBlue) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(title: "앱 시작 시간", value: formattedLaunchTime, icon: "clock.fill", color: .blue)
                        StatCard(title: "현재 상태", value: appState.playerViewModel?.streamPhase == .playing ? "재생 중" : "대기", icon: "play.circle.fill", color: .green)
                        StatCard(title: "로그인", value: appState.isLoggedIn ? "로그인됨" : "비로그인", icon: "person.fill", color: .purple)
                    }
                }
                
                // Player State
                statsSection("플레이어 상태", icon: "play.rectangle.fill", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "채널",
                            value: appState.playerViewModel?.channelName ?? "-",
                            icon: "tv",
                            color: .orange
                        )
                        StatCard(
                            title: "화질",
                            value: appState.playerViewModel?.currentQuality?.name ?? "-",
                            icon: "sparkles.tv",
                            color: .cyan
                        )
                        StatCard(
                            title: "볼륨",
                            value: "\(Int((appState.playerViewModel?.volume ?? 0) * 100))%",
                            icon: "speaker.wave.2.fill",
                            color: .indigo
                        )
                        StatCard(
                            title: "재생 시간",
                            value: appState.playerViewModel?.formattedUptime ?? "00:00",
                            icon: "timer",
                            color: .mint
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.backgroundDark)
    }
    
    private var formattedLaunchTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: appState.launchTime)
    }
    
    private func statsSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            content()
        }
    }
}

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
                
                statsSection("화질 정보", icon: "sparkles.tv", color: DesignTokens.Colors.accentBlue) {
                    if let qualities = appState.playerViewModel?.availableQualities, !qualities.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(qualities) { q in
                                HStack {
                                    Text(q.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    Spacer()
                                    if q.id == appState.playerViewModel?.currentQuality?.id {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(DesignTokens.Colors.chzzkGreen)
                                                .frame(width: 6, height: 6)
                                            Text("현재")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                        }
                                    }
                                }
                                .padding(DesignTokens.Spacing.sm)
                                .background(
                                    q.id == appState.playerViewModel?.currentQuality?.id
                                        ? DesignTokens.Colors.chzzkGreen.opacity(0.08)
                                        : DesignTokens.Colors.surface
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
        .background(DesignTokens.Colors.backgroundDark)
    }
    
    private func statsSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            content()
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
                    let recentMessages = Array((chatVM?.messages ?? []).suffix(10).reversed())
                    if recentMessages.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 24))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("메시지 없음")
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(recentMessages) { msg in
                                HStack(spacing: 8) {
                                    Text(msg.nickname)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                                        .frame(width: 80, alignment: .leading)
                                        .lineLimit(1)
                                    Text(msg.content)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                            }
                        }
                        .padding(DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.backgroundDark)
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
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
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
                                    .fill(DesignTokens.Colors.surface)
                                    .frame(width: 64, height: 64)
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 24))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Text("시청 기록이 없습니다")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                            Text("라이브 방송을 시청하면 여기에 자동으로 기록됩니다")
                                .font(.system(size: 12))
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
        .background(DesignTokens.Colors.backgroundDark)
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
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 18, alignment: .trailing)

            // 채널명
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            // 진행 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignTokens.Colors.surfaceLight)
                    RoundedRectangle(cornerRadius: 3)
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
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.accentBlue)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    // MARK: - 최근 시청 기록 행

    private func watchHistoryRow(_ record: CViewPersistence.WatchHistoryData) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 썸네일
            if let thumbStr = record.thumbnailURL, let url = URL(string: thumbStr) {
                CachedAsyncImage(url: url) {
                    RoundedRectangle(cornerRadius: 4).fill(DesignTokens.Colors.surfaceLight)
                }
                .frame(width: 54, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignTokens.Colors.surfaceLight)
                    .frame(width: 54, height: 30)
                    .overlay {
                        Image(systemName: "play.tv")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.channelName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let cat = record.categoryName, !cat.isEmpty {
                        Text(cat)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(record.formattedDate)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            Spacer()

            // 시청 시간
            if record.duration > 60 {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(record.formattedDuration)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.Colors.accentOrange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(DesignTokens.Colors.accentOrange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
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
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
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
                    .font(.system(size: 17))
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(
                            isHovered ? color.opacity(0.3) : DesignTokens.Colors.border.opacity(0.2),
                            lineWidth: isHovered ? 1 : 0.5
                        )
                }
        }
        // Metal 3: hover scaleEffect 제거 — GPU texture scale 연산 방지
        // 바닥색+테두리 변경으로만 hover 표현
        .drawingGroup(opaque: false)  // 카드 컨텐츠 단일 Metal 텍스처
        .animation(DesignTokens.Animation.smooth, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }
}
