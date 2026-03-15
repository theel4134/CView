// MARK: - RecentFavoritesView.swift
// CViewApp - 프리미엄 최근 시청 및 즐겨찾기 채널 목록
// Design: 세그먼트 탭 + 프리미엄 채널 카드 + 라이브 상태 실시간 표시

import SwiftUI
import CViewCore
import CViewPersistence
import CViewUI
import CViewNetworking

struct RecentFavoritesView: View {
    
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    
    @State private var recentChannels: [ChannelListData] = []
    @State private var favoriteChannels: [ChannelListData] = []
    @State private var liveStatusMap: [String: Bool] = [:]   // channelId → isLive
    @State private var viewerCountMap: [String: Int] = [:]   // channelId → viewerCount
    @State private var isLoading = false
    @State private var isCheckingLive = false
    @State private var errorMessage: String?
    @State private var selectedTab: FavTab = .favorites
    
    enum FavTab: String, CaseIterable, Identifiable {
        case favorites = "즐겨찾기"
        case recent    = "최근 시청"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .favorites: "star.fill"
            case .recent:    "clock.fill"
            }
        }
        var color: Color {
            switch self {
            case .favorites: .yellow
            case .recent:    DesignTokens.Colors.accentBlue
            }
        }
    }
    
    private var currentChannels: [ChannelListData] {
        selectedTab == .favorites ? favoriteChannels : recentChannels
    }

    var body: some View {
        VStack(spacing: 0) {
            // 탭 바 + 요약 배지
            tabHeaderBar
            Divider().overlay(DesignTokens.Glass.borderColorLight)

            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    // 라이브 현황 배지
                    let liveCount = currentChannels.filter { liveStatusMap[$0.channelId] == true }.count
                    if liveCount > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DesignTokens.Colors.live)
                                .frame(width: 7, height: 7)
                                .shadow(color: DesignTokens.Colors.live.opacity(0.6), radius: 3)
                            Text("\(liveCount)개 채널 방송 중")
                                .font(DesignTokens.Typography.captionSemibold)
                                .foregroundStyle(DesignTokens.Colors.live)
                            Spacer()
                            if isCheckingLive {
                                ProgressView().scaleEffect(0.7).tint(DesignTokens.Colors.chzzkGreen)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                    }

                    if currentChannels.isEmpty {
                        emptyState(
                            icon: selectedTab == .favorites ? "star.slash" : "clock",
                            message: selectedTab == .favorites ? "즐겨찾기한 채널이 없습니다" : "최근 시청한 채널이 없습니다"
                        )
                    } else {
                        ForEach(currentChannels) { channel in
                            PremiumChannelRow(
                                item: channel,
                                isLive: liveStatusMap[channel.channelId] == true,
                                viewerCount: viewerCountMap[channel.channelId],
                                onTap: {
                                    router.navigate(to: .live(channelId: channel.channelId))
                                },
                                onToggleFavorite: {
                                    await toggleFavorite(channelId: channel.channelId)
                                }
                            )
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
        .contentBackground()
        .task { await loadData() }
        .refreshable { await loadData() }
        .overlay {
            if isLoading && recentChannels.isEmpty && favoriteChannels.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(DesignTokens.Colors.chzzkGreen)
                    Text("로딩 중...")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .alert("오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Tab Header Bar

    private var tabHeaderBar: some View {
        HStack(spacing: 0) {
            ForEach(FavTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(DesignTokens.Animation.fast) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(DesignTokens.Typography.caption)
                        Text(tab.rawValue)
                            .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                        let count = tab == .favorites ? favoriteChannels.count : recentChannels.count
                        if count > 0 {
                            Text("\(count)")
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(isSelected ? .black : DesignTokens.Colors.textTertiary)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .background {
                                    if isSelected {
                                        tab.color
                                    } else {
                                        Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                                    }
                                }
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(isSelected ? tab.color : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Rectangle()
                                .fill(tab.color)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
            .buttonStyle(.plain)
        }
        .background(DesignTokens.Colors.surfaceOverlay)
    }
    
    // MARK: - Data Loading

    private func loadData() async {
        guard let dataStore = appState.dataStore else { return }
        isLoading = true

        do {
            async let favTask = dataStore.fetchFavoriteItems()
            async let recTask = dataStore.fetchRecentItems(limit: 20)
            let (favs, recs) = try await (favTask, recTask)
            favoriteChannels = favs
            recentChannels = recs
        } catch {
            errorMessage = "데이터 로드 실패: \(error.localizedDescription)"
        }

        isLoading = false
        await refreshLiveStatus()
    }

    private func refreshLiveStatus() async {
        isCheckingLive = true
        defer { isCheckingLive = false }

        let liveItems = appState.homeViewModel?.liveChannels ?? []
        var statusMap: [String: Bool] = [:]
        var viewerMap: [String: Int] = [:]
        for item in liveItems {
            statusMap[item.channelId] = item.isLive
            viewerMap[item.channelId] = item.viewerCount
        }
        liveStatusMap = statusMap
        viewerCountMap = viewerMap
    }

    private func toggleFavorite(channelId: String) async {
        guard let dataStore = appState.dataStore else { return }
        do {
            _ = try await dataStore.toggleFavorite(channelId: channelId)
            await loadData()
        } catch {
            errorMessage = "즐겨찾기 토글 실패"
        }
    }
}

// MARK: - Section Header + Empty State helpers (used in other views)

private extension RecentFavoritesView {
    func emptyState(icon: String, message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(message)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.vertical, DesignTokens.Spacing.xl)
            Spacer()
        }
    }
}

// MARK: - Premium Channel Row (live badge + profile image + viewers)

struct PremiumChannelRow: View {
    let item: ChannelListData
    let isLive: Bool
    let viewerCount: Int?
    let onTap: () -> Void
    let onToggleFavorite: () async -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 채널 아바타 + 라이브 링
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let urlStr = item.imageURL, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) {
                            avatarPlaceholder
                        }
                    } else {
                        avatarPlaceholder
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isLive ? DesignTokens.Colors.live : DesignTokens.Colors.border.opacity(0.6),
                            lineWidth: isLive ? 2.5 : 1
                        )
                )

                if isLive {
                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }

            // 채널 정보
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.channelName)
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if isLive {
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .black))
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.live)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    }
                }
                HStack(spacing: 4) {
                    if isLive, let vc = viewerCount, vc > 0 {
                        Image(systemName: "person.fill")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        Text(formatViewerCount(vc))
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    } else if let lastWatched = item.lastWatched {
                        Image(systemName: "clock")
                            .font(DesignTokens.Typography.micro)
                        Text(lastWatched, style: .relative)
                            .font(DesignTokens.Typography.caption)
                    } else {
                        Text("최근 시청 없음")
                            .font(DesignTokens.Typography.caption)
                    }
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            // 즐겨찾기 버튼
            Button {
                Task { await onToggleFavorite() }
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(item.isFavorite ? .yellow : DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, DesignTokens.Spacing.xxs)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background {
            ZStack {
                if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(isLive ? DesignTokens.Colors.live.opacity(0.07) : DesignTokens.Colors.surfaceOverlay)
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(DesignTokens.Colors.surfaceElevated)
                }
            }
            // 동적 shadow opacity 제거 — hover마다 GPU blur 패스 재계산 방지
            .shadow(
                color: isLive ? DesignTokens.Colors.live.opacity(0.12) : .clear,
                radius: 6
            )
        }
        .contentShape(Rectangle())
        // Metal 3: hover scaleEffect 제거 — GPU texture scale 연산 방지
        .animation(DesignTokens.Animation.fast, value: isHovered)
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovered = hovering
        }
        .customCursor(.pointingHand)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(DesignTokens.Colors.surfaceBase)
            .overlay {
                Image(systemName: "person.fill")
                    .font(DesignTokens.Typography.subhead)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }

    private func formatViewerCount(_ count: Int) -> String {
        if count >= 10000 {
            return String(format: "%.1f만명", Double(count) / 10000)
        } else if count >= 1000 {
            return String(format: "%.1f천명", Double(count) / 1000)
        }
        return "\(count)명"
    }
}

// MARK: - SimpleChannelRow (legacy, kept for compatibility)

struct SimpleChannelRow: View {
    let item: ChannelListData
    let onTap: () -> Void
    let onToggleFavorite: () async -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 채널 이미지 with ring
            if let imageURL = item.imageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 42, height: 42)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            } else {
                channelPlaceholder
            }
            
            // 채널 정보
            VStack(alignment: .leading, spacing: 3) {
                Text(item.channelName)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                
                if let lastWatched = item.lastWatched {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(DesignTokens.Typography.micro)
                        Text(lastWatched, style: .relative)
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // 즐겨찾기 버튼
            Button {
                Task { await onToggleFavorite() }
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(item.isFavorite ? .yellow : DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(isHovered ? DesignTokens.Colors.surfaceOverlay : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.fast) { isHovered = hovering }
        }
        .customCursor(.pointingHand)
    }
    
    private var channelPlaceholder: some View {
        Circle()
            .fill(DesignTokens.Colors.surfaceBase)
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: "person.fill")
                    .font(DesignTokens.Typography.custom(size: 16))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
    }
}
