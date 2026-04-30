// MARK: - ChannelInfoView.swift
// CViewApp - 채널 상세 정보 뷰 (메인 컨테이너)
// 리팩토링: 히어로 헤더/ 탭 콘텐츠/ 미디어 카드/ 메모 시트를 별도 파일로 분리

import SwiftUI
import CViewCore
import CViewNetworking
import CViewPersistence
import CViewUI

// MARK: - Tab Enum

enum ChannelTab: String, CaseIterable, Identifiable {
    case info = "정보"
    case vod  = "VOD"
    case clip = "클립"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .info: "person.text.rectangle.fill"
        case .vod:  "play.rectangle.fill"
        case .clip: "scissors"
        }
    }
}

// MARK: - Shared Formatters

func formatChannelNumber(_ n: Int) -> String {
    if n >= 10_000 {
        let man = Double(n) / 10_000.0
        return String(format: "%.1f만", man)
    }
    if n >= 1_000 {
        let k = Double(n) / 1_000.0
        return String(format: "%.1fK", k)
    }
    return n.formatted()
}

func formatChannelUptime(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}

// MARK: - ChannelInfoView

struct ChannelInfoView: View {
    let channelId: String

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    // Data
    @State private var channelInfo: ChannelInfo?
    @State private var liveInfo: LiveInfo?
    @State private var vodList: [VODInfo] = []
    @State private var clipList: [ClipInfo] = []

    // Pagination
    @State private var vodPage: Int = 0
    @State private var clipPage: Int = 0
    @State private var hasMoreVODs = true
    @State private var hasMoreClips = true
    @State private var isLoadingMoreVODs = false
    @State private var isLoadingMoreClips = false

    // UI state
    @State private var isLoading = true
    @State private var isFavorite = false
    @State private var isFollowing = false
    @State private var errorMessage: String?
    @State private var selectedTab: ChannelTab = .info
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var tabNS

    // Memo
    @State private var channelMemo: String = ""
    @State private var showMemoSheet = false

    // Info tab UI state
    @State private var isDescExpanded = false
    @State private var urlCopied = false

    // Live uptime timer
    @State private var liveUptime: TimeInterval = 0
    @State private var uptimeTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let info = channelInfo {
                    // 히어로 헤더
                    ChannelInfoHeroHeader(
                        channelInfo: info,
                        liveInfo: liveInfo
                    )
                    // 퀵 액션 바
                    ChannelInfoQuickActionBar(
                        channelId: channelId,
                        liveInfo: liveInfo,
                        isFavorite: $isFavorite,
                        channelMemo: channelMemo,
                        showMemoSheet: $showMemoSheet,
                        onToggleFavorite: { Task { await toggleFavorite() } }
                    )
                    .padding(.top, DesignTokens.Spacing.md)
                    // 커스텀 탭 바
                    tabBar
                        .padding(.top, DesignTokens.Spacing.md)
                    // 탭 콘텐츠
                    tabContent(info)
                        .padding(.top, DesignTokens.Spacing.sm)
                }
            }
        }
        .contentBackground()
        .navigationTitle(channelInfo?.channelName ?? "채널")
        .toolbar { toolbarContent }
        .task { await loadChannelData() }
        .onDisappear { stopUptimeTimer() }
        .sheet(isPresented: $showMemoSheet) {
            ChannelMemoSheet(
                channelName: channelInfo?.channelName ?? "",
                memo: $channelMemo
            ) { newMemo in
                Task {
                    if let ds = appState.dataStore {
                        try? await ds.saveMemo(channelId: channelId, memo: newMemo)
                    }
                }
            }
        }
    }

    // MARK: - Loading / Error (Skeleton)

    private var loadingView: some View {
        VStack(spacing: 0) {
            // Hero header skeleton
            VStack(spacing: DesignTokens.Spacing.sm) {
                // Banner placeholder
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(height: 140)
                    .shimmer()

                // Avatar + name row
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Circle()
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 64, height: 64)
                        .shimmer()
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 140, height: 14)
                            .shimmer()
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 90, height: 10)
                            .shimmer()
                    }
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // Quick action bar skeleton
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(height: 34)
                        .shimmer()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.md)

            // Tab bar skeleton
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 60, height: 12)
                        .shimmer()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.md)

            // Content skeleton (stats / description)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                // Stat pills row
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(height: 52)
                            .shimmer()
                    }
                }

                // Description lines
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: i == 2 ? 180 : .infinity, height: 10)
                        .shimmer()
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.md)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accentOrange.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
            }
            Text(message)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") { Task { await loadChannelData() } }
                .buttonStyle(.bordered)
                .tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ChannelTab.allCases) { tab in
                Button {
                    withAnimation(DesignTokens.Animation.indicator) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(DesignTokens.Typography.custom(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            Text(tab.rawValue)
                                .font(DesignTokens.Typography.custom(size: 13, weight: selectedTab == tab ? .bold : .medium))
                        }
                        .foregroundStyle(
                            selectedTab == tab
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Colors.textSecondary
                        )
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                            }
                        }

                        if selectedTab == tab {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.5)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "tabUnderline", in: tabNS)
                                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.5), radius: 4)
                        } else {
                            Color.clear.frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .animation(DesignTokens.Animation.indicator, value: selectedTab)
            }
        }
        .background {
            VStack {
                Spacer()
                Rectangle()
                    .fill(DesignTokens.Glass.borderColor)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ info: ChannelInfo) -> some View {
        switch selectedTab {
        case .info:
            ChannelInfoTabContent(
                channelInfo: info,
                liveInfo: liveInfo,
                liveUptime: liveUptime,
                channelId: channelId,
                vodList: vodList,
                clipList: clipList,
                hasMoreVODs: hasMoreVODs,
                hasMoreClips: hasMoreClips,
                channelMemo: $channelMemo,
                showMemoSheet: $showMemoSheet,
                isDescExpanded: $isDescExpanded,
                urlCopied: $urlCopied,
                selectedTab: $selectedTab
            )
        case .vod:
            ChannelVODTab(
                vodList: vodList,
                hasMoreVODs: hasMoreVODs,
                isLoadingMore: isLoadingMoreVODs,
                onLoadMore: { await loadMoreVODs() }
            )
        case .clip:
            ChannelClipTab(
                clipList: clipList,
                hasMoreClips: hasMoreClips,
                isLoadingMore: isLoadingMoreClips,
                onLoadMore: { await loadMoreClips() }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : DesignTokens.Colors.textSecondary)
            }
        }
    }

    // MARK: - Data Loading

    private func loadChannelData() async {
        isLoading = true
        errorMessage = nil

        guard let apiClient = appState.apiClient else {
            errorMessage = "API 클라이언트가 초기화되지 않았습니다"
            isLoading = false
            return
        }

        do {
            async let channelFetch = apiClient.channelInfo(channelId: channelId)
            async let liveFetch: LiveInfo? = { try? await apiClient.liveDetail(channelId: channelId) }()
            async let vodFetch = { (try? await apiClient.vodList(channelId: channelId, page: 0, size: 12).data) ?? [] }()
            async let clipFetch = { (try? await apiClient.clipList(channelId: channelId, page: 0, size: 12).data) ?? [] }()

            let (channel, live, vods, clips) = try await (channelFetch, liveFetch, vodFetch, clipFetch)
            channelInfo = channel
            // status가 .open이 아니면 실제로 방송 중이 아니므로 nil 처리
            liveInfo = (live?.status == .open) ? live : nil
            vodList = vods
            clipList = clips
            vodPage = 0
            clipPage = 0
            hasMoreVODs = vods.count >= 12
            hasMoreClips = clips.count >= 12

            if let openDate = liveInfo?.openDate {
                liveUptime = Date().timeIntervalSince(openDate)
                startUptimeTimer()
            }

            if let ds = appState.dataStore {
                isFavorite = (try? await ds.isFavorite(channelId: channelId)) ?? false
                channelMemo = (try? await ds.fetchMemo(channelId: channelId)) ?? ""
            }

            if let followList = try? await apiClient.following() {
                isFollowing = followList.followingList?.contains(where: { $0.channel?.channelId == channelId }) ?? false
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadMoreVODs() async {
        guard hasMoreVODs, !isLoadingMoreVODs, let apiClient = appState.apiClient else { return }
        isLoadingMoreVODs = true
        let nextPage = vodPage + 1
        do {
            let result = try await apiClient.vodList(channelId: channelId, page: nextPage, size: 12)
            let newVODs = result.data
            if newVODs.isEmpty {
                hasMoreVODs = false
            } else {
                vodList.append(contentsOf: newVODs)
                vodPage = nextPage
                if newVODs.count < 12 { hasMoreVODs = false }
            }
        } catch {
            Log.network.warning("VOD 목록 로드 실패: \(error.localizedDescription, privacy: .public)")
        }
        isLoadingMoreVODs = false
    }

    private func loadMoreClips() async {
        guard hasMoreClips, !isLoadingMoreClips, let apiClient = appState.apiClient else { return }
        isLoadingMoreClips = true
        let nextPage = clipPage + 1
        do {
            let result = try await apiClient.clipList(channelId: channelId, page: nextPage, size: 12)
            let newClips = result.data
            if newClips.isEmpty {
                hasMoreClips = false
            } else {
                clipList.append(contentsOf: newClips)
                clipPage = nextPage
                if newClips.count < 12 { hasMoreClips = false }
            }
        } catch {
            Log.network.warning("클립 목록 로드 실패: \(error.localizedDescription, privacy: .public)")
        }
        isLoadingMoreClips = false
    }

    private func toggleFavorite() async {
        guard let dataStore = appState.dataStore else { return }
        guard let apiClient = appState.apiClient else { return }
        do {
            let info = try await { () async throws -> ChannelInfo in
                if let existing = channelInfo { return existing }
                return try await apiClient.channelInfo(channelId: channelId)
            }()
            try await dataStore.saveChannel(info, isFavorite: !isFavorite)
            isFavorite.toggle()
        } catch {
            Log.app.error("즐겨찾기 토글 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Uptime Timer (Swift Concurrency — Timer.scheduledTimer 대체)

    private func startUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    liveUptime += 1
                }
            }
        }
    }

    private func stopUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = nil
    }
}
