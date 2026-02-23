// MARK: - ChannelInfoView.swift
// CViewApp - 채널 상세 정보 뷰 (리디자인)
// Design: 히어로 배너 + 탭 (정보/VOD/클립) + 통계 + 라이브 방송 카드

import SwiftUI
import Charts
import CViewCore
import CViewNetworking
import CViewPersistence
import CViewUI

// MARK: - Tab Enum

private enum ChannelTab: String, CaseIterable, Identifiable {
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
    @State private var uptimeTimer: Timer? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let info = channelInfo {
                    // 히어로 헤더
                    heroHeader(info)
                    // 퀵 액션 바
                    quickActionBar
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
        .background(DesignTokens.Colors.backgroundDark)
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

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(DesignTokens.Colors.chzzkGreen)
            Text("채널 정보 로딩 중...")
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
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
                    .font(.system(size: 24))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") { Task { await loadChannelData() } }
                .buttonStyle(.bordered)
                .tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Hero Header

    private func heroHeader(_ info: ChannelInfo) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 배너 배경 — 라이브 썸네일 or 그라데이션
            bannerBackground

            // 하단 그라데이션 오버레이
            LinearGradient(
                colors: [.clear, DesignTokens.Colors.backgroundDark.opacity(0.7), DesignTokens.Colors.backgroundDark],
                startPoint: .top,
                endPoint: .bottom
            )

            // 채널 메타 정보
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.md) {
                // 아바타
                ZStack {
                    if liveInfo != nil {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [DesignTokens.Colors.live, DesignTokens.Colors.accentOrange],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 98, height: 98)
                    } else {
                        Circle()
                            .strokeBorder(DesignTokens.Colors.border, lineWidth: 2)
                            .frame(width: 98, height: 98)
                    }
                    CachedAsyncImage(url: info.channelImageURL) {
                        ZStack {
                            Circle().fill(DesignTokens.Colors.surfaceLight)
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                }

                // 채널명 + 배지 + 팔로워
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(info.channelName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .shadow(color: .black.opacity(0.5), radius: 4)

                        if info.verifiedMark {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(DesignTokens.Colors.accentBlue)
                                .font(.system(size: 15))
                        }
                    }

                    HStack(spacing: 8) {
                        if liveInfo != nil {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(DesignTokens.Colors.live)
                                    .frame(width: 7, height: 7)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(DesignTokens.Colors.live)
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text("팔로워 \(formatNumber(info.followerCount))")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
        .frame(height: 200)
        .clipped()
    }

    @ViewBuilder
    private var bannerBackground: some View {
        if let live = liveInfo, let thumbURL = live.liveImageURL ?? live.defaultThumbnailImageURL {
            CachedAsyncImage(url: thumbURL) {
                LinearGradient(
                    colors: [DesignTokens.Colors.chzzkGreen.opacity(0.25), DesignTokens.Colors.backgroundDark],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: 8)
            .scaleEffect(1.05)
        } else {
            LinearGradient(
                colors: [DesignTokens.Colors.surface, DesignTokens.Colors.backgroundDark],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Quick Action Bar

    @ViewBuilder
    private var quickActionBar: some View {
        HStack(spacing: 10) {
            // 라이브 시청
            if liveInfo != nil {
                quickActionButton(
                    title: "바로 시청",
                    icon: "play.fill",
                    color: DesignTokens.Colors.chzzkGreen,
                    style: .filled
                ) {
                    router.navigate(to: .live(channelId: channelId))
                }

                quickActionButton(
                    title: "채팅만 보기",
                    icon: "bubble.left.fill",
                    color: DesignTokens.Colors.accentBlue,
                    style: .outlined
                ) {
                    router.navigate(to: .chatOnly(channelId: channelId))
                }
            }

            // 즐겨찾기
            quickActionButton(
                title: isFavorite ? "즐겨찾기됨" : "즐겨찾기",
                icon: isFavorite ? "star.fill" : "star",
                color: .yellow,
                style: isFavorite ? .tinted : .outlined
            ) {
                Task { await toggleFavorite() }
            }

            // 치지직에서 열기
            quickActionButton(
                title: "치지직 열기",
                icon: "arrow.up.right.square",
                color: DesignTokens.Colors.textSecondary,
                style: .outlined
            ) {
                if let url = URL(string: "https://chzzk.naver.com/\(channelId)") {
                    NSWorkspace.shared.open(url)
                }
            }

            // 메모
            quickActionButton(
                title: channelMemo.isEmpty ? "메모" : "메모 있음",
                icon: channelMemo.isEmpty ? "note.text" : "note.text.badge.plus",
                color: .orange,
                style: channelMemo.isEmpty ? .outlined : .tinted
            ) {
                showMemoSheet = true
            }

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    private enum QuickActionStyle { case filled, outlined, tinted }

    private func quickActionButton(
        title: String, icon: String, color: Color,
        style: QuickActionStyle, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(style == .filled ? .black : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                switch style {
                case .filled:
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(color)
                case .outlined:
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
                        }
                case .tinted:
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(color.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ChannelTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                        }
                        .foregroundStyle(
                            selectedTab == tab
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Colors.textSecondary
                        )
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)

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
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedTab)
            }
        }
        .background {
            VStack {
                Spacer()
                Rectangle()
                    .fill(DesignTokens.Colors.border.opacity(0.35))
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
            infoTab(info)
        case .vod:
            vodTab
        case .clip:
            clipTab
        }
    }

    // MARK: - 정보 탭

    private func infoTab(_ info: ChannelInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            // 라이브 방송 카드 (라이브 중일 때)
            if let live = liveInfo {
                liveCard(live)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 채널 통계 그리드
            statsGrid(info)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            // 채널 소개
            if let desc = info.channelDescription, !desc.isEmpty {
                channelDescSection(desc)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 채널 메모 인라인 카드
            if !channelMemo.isEmpty {
                channelMemoCard
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 최근 VOD 미리보기
            if !vodList.isEmpty {
                recentVodPreview
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 최근 클립 미리보기
            if !clipList.isEmpty {
                recentClipPreview
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 채널 URL 공유 카드
            channelShareSection(channelId: info.channelId)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer(minLength: DesignTokens.Spacing.xl)
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }

    // 라이브 방송 카드
    private func liveCard(_ live: LiveInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 섹션 헤더
            HStack(spacing: 6) {
                Circle().fill(DesignTokens.Colors.live).frame(width: 8, height: 8)
                Text("현재 방송 중")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                // 방송 시간
                if liveUptime > 0 {
                    Text(formatUptime(liveUptime))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Button {
                router.navigate(to: .live(channelId: channelId))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // 썸네일
                    ZStack(alignment: .bottomLeading) {
                        if let thumb = live.liveImageURL ?? live.defaultThumbnailImageURL {
                            CachedAsyncImage(url: thumb) {
                                Rectangle().fill(DesignTokens.Colors.surfaceLight)
                                    .overlay {
                                        Image(systemName: "play.tv")
                                            .font(.system(size: 28))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                            }
                        } else {
                            Rectangle().fill(DesignTokens.Colors.surfaceLight)
                                .overlay {
                                    Image(systemName: "play.tv")
                                        .font(.system(size: 28))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                        }
                        // 시청자 + LIVE 오버레이
                        HStack(spacing: 6) {
                            Text("LIVE")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DesignTokens.Colors.live)
                                .clipShape(Capsule())

                            HStack(spacing: 3) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                Text("\(formatNumber(live.concurrentUserCount))명")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                        }
                        .padding(8)

                        // 재생 버튼 오버레이
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.45))
                                .frame(width: 52, height: 52)
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .clipped()

                    // 방송 메타
                    VStack(alignment: .leading, spacing: 6) {
                        Text(live.liveTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if let cat = live.liveCategoryValue ?? live.liveCategory {
                                Text(cat)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            if live.adult {
                                Text("19+")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(DesignTokens.Colors.live)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.Colors.live.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }

                        // 태그
                        if !live.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(live.tags.prefix(8), id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(DesignTokens.Colors.surfaceLight)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.surface)
                }
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(DesignTokens.Colors.live.opacity(0.25), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // 통계 그리드
    private func statsGrid(_ info: ChannelInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("채널 통계")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: DesignTokens.Spacing.sm
            ) {
                channelStatCard(
                    icon: "person.2.fill",
                    label: "팔로워",
                    value: formatNumber(info.followerCount),
                    color: DesignTokens.Colors.accentPurple
                )

                channelStatCard(
                    icon: liveInfo != nil ? "dot.radiowaves.left.and.right" : "moon.fill",
                    label: "방송 상태",
                    value: liveInfo != nil ? "라이브" : "오프라인",
                    color: liveInfo != nil ? DesignTokens.Colors.live : DesignTokens.Colors.textTertiary
                )

                channelStatCard(
                    icon: "person.fill",
                    label: "현재 시청",
                    value: liveInfo != nil ? "\(formatNumber(liveInfo!.concurrentUserCount))명" : "-",
                    color: DesignTokens.Colors.chzzkGreen
                )

                channelStatCard(
                    icon: "play.rectangle.fill",
                    label: "VOD",
                    value: hasMoreVODs ? "\(vodList.count)+" : "\(vodList.count)개",
                    color: DesignTokens.Colors.accentBlue
                )

                channelStatCard(
                    icon: "scissors",
                    label: "클립",
                    value: hasMoreClips ? "\(clipList.count)+" : "\(clipList.count)개",
                    color: DesignTokens.Colors.accentOrange
                )

                if let live = liveInfo, let openDate = live.openDate {
                    let formatter = RelativeDateTimeFormatter()
                    let _ = formatter.unitsStyle = .abbreviated
                    channelStatCard(
                        icon: "clock.fill",
                        label: "방송 시작",
                        value: formatter.localizedString(for: openDate, relativeTo: Date()),
                        color: DesignTokens.Colors.warning
                    )
                } else if info.verifiedMark {
                    channelStatCard(
                        icon: "checkmark.seal.fill",
                        label: "인증",
                        value: "파트너",
                        color: DesignTokens.Colors.accentBlue
                    )
                } else {
                    channelStatCard(
                        icon: "checkmark.seal",
                        label: "인증",
                        value: "일반",
                        color: DesignTokens.Colors.textTertiary
                    )
                }
            }
        }
    }

    private func channelStatCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        }
    }

    // 채널 소개
    private func channelDescSection(_ desc: String) -> some View {
        let isLong = desc.count > 120
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("채널 소개")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                if isLong {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isDescExpanded.toggle() }
                    } label: {
                        Text(isDescExpanded ? "접기" : "더 보기")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(desc)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(isLong && !isDescExpanded ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // 채널 메모 인라인 카드
    private var channelMemoCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                Text("내 메모")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button {
                    showMemoSheet = true
                } label: {
                    Text("편집")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            Text(channelMemo)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.8)
                }
        }
    }

    // 채널 URL 공유 카드
    private func channelShareSection(channelId: String) -> some View {
        let url = "https://chzzk.naver.com/\(channelId)"
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("채널 주소")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    withAnimation { urlCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { urlCopied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: urlCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(urlCopied ? "복사됨" : "복사")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(urlCopied ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(urlCopied ? DesignTokens.Colors.chzzkGreen.opacity(0.12) : DesignTokens.Colors.surfaceLight)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // 정보 탭 내 클립 미리보기
    private var recentClipPreview: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "scissors")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                Text("최근 클립")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button {
                    withAnimation { selectedTab = .clip }
                } label: {
                    Text("전체 보기")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(clipList.prefix(5)) { clip in
                        CompactClipCard(clip: clip) {
                            router.navigate(to: .clip(clipUID: clip.clipUID))
                        }
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    // 정보 탭 내 VOD 미리보기 3개
    private var recentVodPreview: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                Text("최근 VOD")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button {
                    withAnimation { selectedTab = .vod }
                } label: {
                    Text("전체 보기")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(vodList.prefix(5)) { vod in
                        CompactVODCard(vod: vod) {
                            router.navigate(to: .vod(videoNo: vod.videoNo))
                        }
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    // MARK: - VOD 탭

    private var vodTab: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("전체 VOD")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(hasMoreVODs ? "\(vodList.count)+" : "\(vodList.count)개")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            if vodList.isEmpty && !isLoadingMoreVODs {
                emptyState(icon: "play.rectangle", message: "VOD가 없습니다")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: DesignTokens.Spacing.md)],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(vodList) { vod in
                        VODCard(vod: vod) {
                            router.navigate(to: .vod(videoNo: vod.videoNo))
                        }
                        .onAppear {
                            if vod.id == vodList.last?.id { Task { await loadMoreVODs() } }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                if isLoadingMoreVODs {
                    loadMoreIndicator
                }
            }

            Spacer(minLength: DesignTokens.Spacing.xl)
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }

    // MARK: - 클립 탭

    private var clipTab: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("전체 클립")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(hasMoreClips ? "\(clipList.count)+" : "\(clipList.count)개")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            if clipList.isEmpty && !isLoadingMoreClips {
                emptyState(icon: "scissors", message: "클립이 없습니다")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: DesignTokens.Spacing.md)],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(clipList) { clip in
                        ClipCard(clip: clip) {
                            router.navigate(to: .clip(clipUID: clip.clipUID))
                        }
                        .onAppear {
                            if clip.id == clipList.last?.id { Task { await loadMoreClips() } }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                if isLoadingMoreClips {
                    loadMoreIndicator
                }
            }

            Spacer(minLength: DesignTokens.Spacing.xl)
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var loadMoreIndicator: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
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
            liveInfo = live
            vodList = vods
            clipList = clips
            vodPage = 0
            clipPage = 0
            hasMoreVODs = vods.count >= 12
            hasMoreClips = clips.count >= 12

            if let openDate = live?.openDate {
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
        } catch { }
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
        } catch { }
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

    // MARK: - Uptime Timer

    private func startUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            liveUptime += 1
        }
    }

    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
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

    private func formatUptime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Compact VOD Card (정보 탭 가로스크롤용)

private struct CompactVODCard: View {
    let vod: VODInfo
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: vod.videoImageURL) {
                        Rectangle().fill(DesignTokens.Colors.surfaceLight)
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .clipped()

                    Text(vod.formattedDuration)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(5)
                }

                Text(vod.videoTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)

                HStack(spacing: 3) {
                    Image(systemName: "eye").font(.system(size: 9))
                    Text(vod.readCount.formatted())
                        .font(.system(size: 10))
                    if let publishDate = vod.publishDate {
                        Text("·").font(.system(size: 10))
                        Text(publishDate, style: .relative)
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : DesignTokens.Colors.surface)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Compact Clip Card (정보 탭 가로스크롤용)

private struct CompactClipCard: View {
    let clip: ClipInfo
    let onTap: () -> Void
    @State private var isHovered = false

    private var formattedDuration: String {
        let total = clip.duration
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .overlay {
                            CachedAsyncImage(url: clip.thumbnailImageURL) {
                                Rectangle().fill(DesignTokens.Colors.surfaceLight)
                                    .overlay {
                                        Image(systemName: "scissors")
                                            .font(.system(size: 18))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                    Text(formattedDuration)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(5)
                }

                Text(clip.clipTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)

                HStack(spacing: 3) {
                    Image(systemName: "scissors").font(.system(size: 9))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                    Text(clip.readCount.formatted())
                        .font(.system(size: 10))
                    if let createdDate = clip.createdDate {
                        Text("·").font(.system(size: 10))
                        Text(createdDate, style: .relative)
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : DesignTokens.Colors.surface)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Premium VOD Card (VOD 탭용)

private struct VODCard: View {
    let vod: VODInfo
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: vod.videoImageURL) {
                        Rectangle().fill(DesignTokens.Colors.surfaceLight)
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .font(.title2)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .clipped()

                    Text(vod.formattedDuration)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }

                Text(vod.videoTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye").font(.system(size: 9))
                        Text(vod.readCount.formatted())
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                    if let publishDate = vod.publishDate {
                        Text("·")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(.system(size: 11))
                        Text(publishDate, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Clip Card

private struct ClipCard: View {
    let clip: ClipInfo
    let onTap: () -> Void
    @State private var isHovered = false

    private var formattedDuration: String {
        let total = clip.duration
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .overlay {
                        CachedAsyncImage(url: clip.thumbnailImageURL) {
                            Rectangle().fill(DesignTokens.Colors.surfaceLight)
                                .overlay {
                                    Image(systemName: "scissors")
                                        .font(.title2)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .overlay(alignment: .bottomTrailing) {
                        // 클립 시간 뱃지
                        Text(formattedDuration)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.75))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                        // 클립 아이콘
                        Image(systemName: "scissors")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.Colors.accentOrange)
                            .padding(6)
                            .background(.black.opacity(0.6))
                            .clipShape(Circle())
                            .padding(6)
                    }

                Text(clip.clipTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(height: 34, alignment: .topLeading)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye").font(.system(size: 9))
                        Text(clip.readCount.formatted())
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                    if let createdDate = clip.createdDate {
                        Text("·")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .font(.system(size: 11))
                        Text(createdDate, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(isHovered ? DesignTokens.Colors.surfaceHover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}


// MARK: - Channel Memo Sheet

private struct ChannelMemoSheet: View {
    let channelName: String
    @Binding var memo: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedMemo: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(channelName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(DesignTokens.Spacing.lg)

            Divider().background(DesignTokens.Colors.border)

            TextEditor(text: $editedMemo)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(DesignTokens.Spacing.sm)
                .background(DesignTokens.Colors.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(focused ? Color.orange.opacity(0.6) : DesignTokens.Colors.border, lineWidth: 1)
                )
                .focused($focused)
                .padding(DesignTokens.Spacing.lg)

            HStack {
                Spacer()
                Text("\(editedMemo.count)자")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xs)

            Divider().background(DesignTokens.Colors.border)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
                    .buttonStyle(.bordered)

                Button("저장") {
                    onSave(editedMemo)
                    memo = editedMemo
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .frame(width: 480, height: 360)
        .background(DesignTokens.Colors.backgroundDark)
        .onAppear {
            editedMemo = memo
            focused = true
        }
    }
}
