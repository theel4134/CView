// MARK: - FollowingView+Redesign2026.swift
// 2026-04-27 라이브 메뉴 최종 리디자인 — Overview Stage + Right Chat Dock + Bottom Following Sheet
//
// 도큐먼트: docs/live-menu-final-overview-following-redesign-2026-04-27.md
// "탐색 첫 화면은 팔로잉 종합 정보, 팔로잉 목록은 하단에서 올라오는 예쁜 live deck, 우측은 채팅 전용."

import SwiftUI
import CViewCore
import CViewChat
import CViewUI

extension FollowingView {

    // MARK: - Overview Stage (탐색 모드 첫 화면)

    var overviewStage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {

                // 1) 헤더 — 모드 설명 + 빠른 액션
                overviewHeader

                // 2) 팔로잉 라이브 요약 (4개 카드 — 인터랙티브)
                overviewSummaryCards

                // 3) 최근 시청 라이브 채널 (2개 이상일 때 표시)
                overviewRecentSection

                // 4) Up Next — 즐겨찾기 우선 정렬, 전체 보기 링크
                overviewUpNextSection

                // 5) Active MultiLive — 이미 열려 있는 세션 요약
                if !multiLiveManager.sessions.isEmpty {
                    overviewActiveSessionsSection
                }

                // 6) Alerts & Quality — 셌션 상태 / 엔진 구성 / 네트워크 · 메트릭 윈도우 링크
                overviewAlertsSection

                // 7) Quick Actions
                overviewQuickActions

                // sheet가 peek/expanded일 때 하단 가림 방지용 여백
                Color.clear.frame(height: bottomSheetReservedSpace)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.background)
    }

    private var overviewHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("팔로잉 종합")
                    .font(DesignTokens.Typography.custom(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("지금 라이브 중인 팔로잉과 추천을 한눈에. 카드를 누르면 시청 또는 멀티로 이어집니다.")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    ps.followingSheetState = ps.followingSheetState == .expanded ? .peek : .expanded
                }
            } label: {
                Label(
                    ps.followingSheetState == .expanded ? "시트 접기" : "팔로잉 시트",
                    systemImage: ps.followingSheetState == .expanded ? "chevron.down" : "rectangle.portrait.and.arrow.up"
                )
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.14)))
                .overlay(Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 0.6))
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        }
    }

    private var overviewSummaryCards: some View {
        let liveCount = cachedLive.count
        let totalViewers = cachedLive.reduce(0) { $0 + $1.viewerCount }
        let topCategory = cachedLiveCategoryCounts.first?.name ?? "—"
        let activeSessions = multiLiveManager.sessions.count

        return HStack(spacing: DesignTokens.Spacing.md) {
            overviewSummaryCard(
                icon: "antenna.radiowaves.left.and.right",
                tint: DesignTokens.Colors.live,
                title: "팔로잉 라이브",
                value: "\(liveCount)",
                detail: "지금 방송 중",
                action: { withAnimation(DesignTokens.Animation.snappy) { ps.followingSheetState = .expanded } }
            )
            overviewSummaryCard(
                icon: "eye.fill",
                tint: DesignTokens.Colors.accentBlue,
                title: "총 시청자",
                value: formatShortCount(totalViewers),
                detail: "팔로잉 합계",
                action: { withAnimation(DesignTokens.Animation.snappy) { ps.followingSheetState = .expanded } }
            )
            overviewSummaryCard(
                icon: "tag.fill",
                tint: DesignTokens.Colors.accentOrange,
                title: "주요 카테고리",
                value: topCategory,
                detail: cachedLiveCategoryCounts.first.map { "\($0.count)개 채널" } ?? "—",
                action: { router.selectedSidebarItem = .category }
            )
            overviewSummaryCard(
                icon: "rectangle.3.group",
                tint: DesignTokens.Colors.chzzkGreen,
                title: "멀티 세션",
                value: "\(activeSessions)",
                detail: "활성 / 최대 \(multiLiveManager.effectiveMaxSessions)",
                action: activeSessions > 0 ? { applyHubModePreset(.multi) } : nil
            )
        }
    }

    // MARK: Summary Card — body + interactive wrapper

    private func summaryCardBody(icon: String, tint: Color, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(DesignTokens.Typography.custom(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func overviewSummaryCard(icon: String, tint: Color, title: String, value: String, detail: String, action: (() -> Void)? = nil) -> some View {
        if let action {
            Button(action: action) {
                summaryCardBody(icon: icon, tint: tint, title: title, value: value, detail: detail)
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.97))
            .help("탭하여 이동")
        } else {
            summaryCardBody(icon: icon, tint: tint, title: title, value: value, detail: detail)
        }
    }

    @ViewBuilder
    private var overviewUpNextSection: some View {
        if cachedLive.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                overviewSectionHeader(
                    title: "Up Next",
                    subtitle: "지금 볼 만한 라이브",
                    trailingTitle: cachedLive.count > 8 ? "전체 보기" : nil,
                    trailingAction: cachedLive.count > 8 ? {
                        withAnimation(DesignTokens.Animation.snappy) { ps.followingSheetState = .expanded }
                    } : nil
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        ForEach(sortedUpNextChannels().prefix(8), id: \.channelId) { channel in
                            overviewUpNextCard(channel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// 즐겨찾기 채널 우선 정렬 — Up Next 섹션용.
    private func sortedUpNextChannels() -> [LiveChannelItem] {
        cachedLive.sorted { a, b in
            let af = ps.favoriteChannelIds.contains(a.channelId)
            let bf = ps.favoriteChannelIds.contains(b.channelId)
            return af && !bf
        }
    }

    private func overviewUpNextCard(_ channel: LiveChannelItem) -> some View {
        Button {
            openChannelForWatch(channel)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if let url = channel.thumbnailUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                DesignTokens.Colors.surfaceBase
                            }
                        }
                        .frame(width: 220, height: 124)
                        .clipped()
                    } else {
                        DesignTokens.Colors.surfaceBase
                            .frame(width: 220, height: 124)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(DesignTokens.Colors.live).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    avatarCircle(url: channel.channelImageUrl, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.channelName)
                            .font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        Text("\(channel.formattedViewerCount) 시청 · \(channel.categoryName ?? "—")")
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text(channel.liveTitle)
                    .font(DesignTokens.Typography.custom(size: 11.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 32, alignment: .top)
            }
            .frame(width: 220, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.6)
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
        .contextMenu {
            Button("시청 모드로 열기") { openChannelForWatch(channel) }
            Button("멀티에 추가") { addChannelToMulti(channel) }
            Button("Smart Queue 담기") { toggleQueue(channel.channelId) }
        }
    }

    @ViewBuilder
    private var overviewActiveSessionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            overviewSectionHeader(title: "Active MultiLive", subtitle: "현재 열려 있는 세션")

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(multiLiveManager.sessions, id: \.id) { session in
                    Button {
                        multiLiveManager.select(session)
                        applyHubModePreset(.multi)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.18))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Image(systemName: "play.fill")
                                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                }
                            Text(session.channelName)
                                .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(DesignTokens.Colors.surfaceElevated.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.6))
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.96))
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Alerts & Quality

    private var overviewAlertsSection: some View {
        let sessions = multiLiveManager.sessions
        let total = sessions.count
        let buffering = sessions.filter {
            if case .loading = $0.loadState { return true }
            if case .error = $0.loadState { return true }
            return false
        }.count
        let offline = sessions.filter { $0.isOffline }.count
        let vlcCount = sessions.filter { $0.latestMetrics != nil }.count
        let avCount = sessions.filter { $0.latestAVMetrics != nil }.count

        // [2026-04-28 P2] Compact insight — 집계 메트릭
        let avLatencies = sessions.compactMap { $0.latestAVMetrics?.measuredLatency }.filter { $0 > 0 }
        let avgLatency: Double = avLatencies.isEmpty ? 0 : avLatencies.reduce(0, +) / Double(avLatencies.count)
        let maxLatency: Double = avLatencies.max() ?? 0
        let vlcFps = sessions.compactMap { $0.latestMetrics?.fps }.filter { $0 > 0 }
        let avgFps: Double = vlcFps.isEmpty ? 0 : vlcFps.reduce(0, +) / Double(vlcFps.count)
        let totalDrops: Int = sessions.reduce(0) { acc, s in
            acc + (s.latestMetrics?.droppedFramesDelta ?? 0) + (s.latestAVMetrics?.droppedFramesDelta ?? 0)
        }
        let avHealth = sessions.compactMap { $0.latestAVMetrics?.healthScore }
        let avgHealth: Double = avHealth.isEmpty ? 0 : avHealth.reduce(0, +) / Double(avHealth.count)
        let hasMetrics = !avLatencies.isEmpty || !vlcFps.isEmpty

        let healthy = total > 0 && buffering == 0 && offline == 0
        let statusTint: Color = healthy
            ? DesignTokens.Colors.chzzkGreen
            : (buffering > 0 ? DesignTokens.Colors.warning : DesignTokens.Colors.textTertiary)
        let statusText: String = total == 0
            ? "세션 없음"
            : (healthy ? "Metrics 정상" : "주의 필요")

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            overviewSectionHeader(title: "Alerts & Quality", subtitle: "재생 품질 · 네트워크")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(statusTint).frame(width: 8, height: 8)
                        Text(statusText)
                            .font(DesignTokens.Typography.custom(size: 12, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(statusTint.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(statusTint.opacity(0.28), lineWidth: 0.6))

                    alertChip(label: "세션", value: "\(total)/\(multiLiveManager.effectiveMaxSessions)", tint: DesignTokens.Colors.chzzkGreen)
                    alertChip(label: "버퍼 경고", value: "\(buffering)", tint: buffering > 0 ? DesignTokens.Colors.warning : DesignTokens.Colors.textSecondary)
                    alertChip(label: "오프라인", value: "\(offline)", tint: offline > 0 ? DesignTokens.Colors.live : DesignTokens.Colors.textSecondary)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    engineBadge(name: "VLC", count: vlcCount, tint: DesignTokens.Colors.accentOrange)
                    engineBadge(name: "AVPlayer", count: avCount, tint: DesignTokens.Colors.accentBlue)
                    Text(total == 0 ? "멀티라이브 세션이 열린 후 상세 메트릭이 표시됩니다." : "자세한 도표는 도구창에서 확인")
                        .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    alertActionButton(icon: "network", title: "네트워크") {
                        openWindow(id: "ml-network-window")
                    }
                    alertActionButton(icon: "chart.line.uptrend.xyaxis", title: "메트릭") {
                        openWindow(id: "ml-metrics-window")
                    }
                }

                // [2026-04-28 P2] Compact insight — 집계 메트릭 행
                if hasMetrics {
                    HStack(spacing: 8) {
                        if !avLatencies.isEmpty {
                            metricInsightChip(
                                icon: "timer",
                                label: "평균 지연",
                                value: String(format: "%.1fs", avgLatency),
                                tint: avgLatency < 5 ? DesignTokens.Colors.chzzkGreen : (avgLatency < 8 ? DesignTokens.Colors.warning : DesignTokens.Colors.live)
                            )
                            if maxLatency > avgLatency + 0.5 {
                                metricInsightChip(
                                    icon: "exclamationmark.triangle",
                                    label: "최대",
                                    value: String(format: "%.1fs", maxLatency),
                                    tint: DesignTokens.Colors.textSecondary
                                )
                            }
                        }
                        if !vlcFps.isEmpty {
                            metricInsightChip(
                                icon: "speedometer",
                                label: "평균 FPS",
                                value: String(format: "%.0f", avgFps),
                                tint: avgFps >= 25 ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.warning
                            )
                        }
                        if totalDrops > 0 {
                            metricInsightChip(
                                icon: "rectangle.slash",
                                label: "드롭",
                                value: "\(totalDrops)",
                                tint: totalDrops > 5 ? DesignTokens.Colors.live : DesignTokens.Colors.warning
                            )
                        }
                        if !avHealth.isEmpty {
                            let pct = Int(avgHealth * 100)
                            metricInsightChip(
                                icon: "heart.text.square",
                                label: "건강도",
                                value: "\(pct)%",
                                tint: pct >= 80 ? DesignTokens.Colors.chzzkGreen : (pct >= 60 ? DesignTokens.Colors.warning : DesignTokens.Colors.live)
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.6)
            )
        }
    }

    private func alertChip(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(DesignTokens.Colors.surfaceBase.opacity(0.7)))
        .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.5))
    }

    private func engineBadge(name: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text("\(name) \(count)")
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    /// [2026-04-28 P2] 집계 메트릭 compact 칩 — 평균 지연/FPS/드롭/건강도 표시.
    private func metricInsightChip(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(tint.opacity(0.10)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
    }

    private func alertActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(DesignTokens.Colors.surfaceBase.opacity(0.85)))
            .overlay(Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.5), lineWidth: 0.6))
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
    }

    private var overviewQuickActions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            overviewSectionHeader(title: "Quick Actions", subtitle: "빠른 전환")
            HStack(spacing: DesignTokens.Spacing.sm) {
                quickActionPill(icon: "play.rectangle", text: "시청으로 이동", tint: DesignTokens.Colors.chzzkGreen) {
                    applyHubModePreset(.watch)
                }
                quickActionPill(icon: "square.grid.2x2", text: "멀티로 이동", tint: DesignTokens.Colors.accentOrange) {
                    applyHubModePreset(.multi)
                }
                quickActionPill(icon: "rectangle.portrait.and.arrow.up", text: "팔로잉 시트", tint: DesignTokens.Colors.accentBlue) {
                    withAnimation(DesignTokens.Animation.snappy) {
                        ps.followingSheetState = .expanded
                    }
                }
                quickActionPill(icon: "square.grid.2x2.fill", text: "카테고리 탐색", tint: Color.purple.opacity(0.85)) {
                    router.selectedSidebarItem = .category
                }
                quickActionPill(icon: "command", text: "Command", tint: DesignTokens.Colors.textSecondary) {
                    appState.showCommandPalette = true
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func quickActionPill(icon: String, text: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                Text(text)
                    .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.6))
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
    }

    private func overviewSectionHeader(title: String, subtitle: String, trailingTitle: String? = nil, trailingAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(subtitle)
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Spacer(minLength: 0)
            if let trailingTitle, let trailingAction {
                Button(action: trailingAction) {
                    Text(trailingTitle)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 최근 시청 라이브 스트립

    @ViewBuilder
    private var overviewRecentSection: some View {
        let recentLive = ps.recentChannelIds.compactMap { id in
            cachedLive.first { $0.channelId == id }
        }
        if recentLive.count >= 2 {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                overviewSectionHeader(title: "최근 시청", subtitle: "이전에 시청한 라이브 채널")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentLive.prefix(8), id: \.channelId) { ch in
                            Button { openChannelForWatch(ch) } label: {
                                VStack(spacing: 4) {
                                    avatarCircle(url: ch.channelImageUrl, size: 42)
                                        .overlay(
                                            Circle().strokeBorder(DesignTokens.Colors.live.opacity(0.75), lineWidth: 1.5)
                                        )
                                    Text(ch.channelName)
                                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 58)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressScaleButtonStyle(scale: 0.95))
                            .help("\(ch.channelName) 시청")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Right Chat Dock (멀티채팅 전용)

    var rightChatDock: some View {
        VStack(spacing: 0) {
            chatDockSection(
                title: "멀티 채팅",
                icon: "bubble.left.and.bubble.right.fill",
                subtitle: chatSessionManager.sessions.isEmpty ? "채널 없음" : "\(chatSessionManager.sessions.count)개 채널"
            )
            multiChatInlinePanel
                .frame(maxHeight: .infinity)
                .clipped()
        }
        .background(DesignTokens.Colors.background)
    }

    private func chatDockSection(title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(title)
                .font(DesignTokens.Typography.custom(size: 11.5, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("·")
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(subtitle)
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: 28)
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.85))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor.opacity(0.4))
                .frame(height: 1)
        }
    }

    // MARK: - Bottom Following Sheet

    /// 모드/상태별로 stage가 가려지지 않도록 예약 공간 (overview 스크롤 패딩용)
    var bottomSheetReservedSpace: CGFloat {
        switch ps.followingSheetState {
        case .collapsed: return 64
        case .peek: return 240
        case .expanded: return 16  // expanded는 어차피 시트가 stage 위 overlay → 적게 잡음
        }
    }

    @ViewBuilder
    func followingBottomSheet(totalWidth: CGFloat, totalHeight: CGFloat) -> some View {
        // [2026-04-30] 시트 높이 정밀 튜닝
        // - collapsed: 핸들+chips 만 (52)
        // - peek: chips + 단일 가로 rail (190~220) — spotlight 제거로 높이 안정화
        // - expanded: 검색/필터 + spotlight + 그리드 (totalHeight 의 46%)
        let height: CGFloat = {
            switch ps.followingSheetState {
            case .collapsed: return 52
            case .peek: return min(max(totalHeight * 0.24, 190), 220)
            case .expanded: return min(max(totalHeight * 0.46, 360), 580)
            }
        }()

        FollowingBottomSheetView(
            state: Binding(get: { ps.followingSheetState }, set: { ps.followingSheetState = $0 }),
            displayMode: Binding(get: { ps.followingDisplayMode }, set: { ps.followingDisplayMode = $0 }),
            filter: Binding(get: { ps.sheetFilter }, set: { ps.sheetFilter = $0 }),
            searchText: Binding(get: { searchText }, set: { searchText = $0 }),
            liveChannels: cachedLive,
            offlineChannels: cachedAllOffline,
            queueIds: smartQueueChannelIds,
            multiSessionCount: multiLiveManager.sessions.count,
            multiSessionMax: multiLiveManager.effectiveMaxSessions,
            favoriteIds: ps.favoriteChannelIds,
            recentIds: ps.recentChannelIds,
            onOpenWatch: { ch in openChannelForWatch(ch) },
            onAddMulti: { ch in addChannelToMulti(ch) },
            onToggleQueue: { id in toggleQueue(id) },
            onClearQueue: { smartQueueChannelIds = [] },
            onFlushQueue: { Task { await performSmartQueueBatchAdd() } },
            onAutoFillQueue: { autoFillSmartQueue() }
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            // [2026-04-30] 시트 배경 톤 조정 — handle/chips/chevron 이 같은 시트 안에
            // 포함되어 보이도록 단일 단색 톤(라이트/다크 모두 적당한 콘트라스트)을 사용.
            // ultraThinMaterial 은 라이트 모드 흰 배경에서 거의 투명해 chips 가 시트
            // 밖으로 떠 보이는 문제가 있어 제거.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.55))
                .shadow(DesignTokens.Shadow.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.6), lineWidth: 0.7)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Shared Actions

    func openChannelForWatch(_ channel: LiveChannelItem) {
        Task {
            await multiLiveManager.addSession(channelId: channel.channelId, presentationOverride: .embedded)
            applyHubModePreset(.watch)
        }
    }

    func addChannelToMulti(_ channel: LiveChannelItem) {
        Task {
            await multiLiveManager.addSession(channelId: channel.channelId, presentationOverride: .embedded)
            applyHubModePreset(.multi)
        }
    }

    func toggleQueue(_ channelId: String) {
        var queue = smartQueueChannelIds
        if let idx = queue.firstIndex(of: channelId) {
            queue.remove(at: idx)
        } else {
            queue.append(channelId)
        }
        smartQueueChannelIds = queue
    }

    // MARK: - Helpers

    @ViewBuilder
    func avatarCircle(url: String?, size: CGFloat) -> some View {
        if let s = url, let u = URL(string: s) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: DesignTokens.Colors.surfaceBase
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.4), lineWidth: 0.5))
        } else {
            Circle()
                .fill(DesignTokens.Colors.surfaceBase)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                )
        }
    }
}

// MARK: - Following Bottom Sheet View

struct FollowingBottomSheetView: View {
    @Binding var state: FollowingSheetState
    @Binding var displayMode: FollowingDisplayMode
    @Binding var filter: FollowingSheetFilter
    @Binding var searchText: String

    let liveChannels: [LiveChannelItem]
    let offlineChannels: [LiveChannelItem]
    let queueIds: [String]
    let multiSessionCount: Int
    let multiSessionMax: Int
    /// [2026-04-28] 즐겨찾기 채널 ID — DataStore에서 주입.
    let favoriteIds: Set<String>
    /// [2026-04-28] 최근 시청 채널 ID — 최신순 배열.
    let recentIds: [String]

    let onOpenWatch: (LiveChannelItem) -> Void
    let onAddMulti: (LiveChannelItem) -> Void
    let onToggleQueue: (String) -> Void
    let onClearQueue: () -> Void
    let onFlushQueue: () -> Void
    /// [2026-04-28 P2] 추천 알고리즘으로 Smart Queue 자동 채우기.
    let onAutoFillQueue: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @State private var hoveredChannelId: String?

    // MARK: - 시트 페이징 (expanded 전용)
    @State private var sheetPage: Int = 0
    private let sheetPageSize: Int = 30

    private var totalSheetPages: Int {
        max(1, Int(ceil(Double(filteredChannels.count) / Double(sheetPageSize))))
    }

    private var pagedChannels: [LiveChannelItem] {
        let start = sheetPage * sheetPageSize
        let end = min(start + sheetPageSize, filteredChannels.count)
        guard start < end else { return [] }
        return Array(filteredChannels[start..<end])
    }

    private var filteredChannels: [LiveChannelItem] {
        let pool: [LiveChannelItem]
        switch filter {
        case .all:
            pool = liveChannels + offlineChannels
        case .live:
            pool = liveChannels
        case .favorites:
            // [2026-04-28] DataStore의 즐겨찾기 채널만 (라이브 우선 노출).
            let all = liveChannels + offlineChannels
            pool = all.filter { favoriteIds.contains($0.channelId) }
        case .recent:
            // [2026-04-28] 최근 시청 순서를 유지한 채로 매칭되는 채널만 통과.
            let map: [String: LiveChannelItem] = Dictionary(
                uniqueKeysWithValues: (liveChannels + offlineChannels).map { ($0.channelId, $0) }
            )
            pool = recentIds.compactMap { map[$0] }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return pool }
        return pool.filter {
            $0.channelName.lowercased().contains(trimmed)
            || $0.liveTitle.lowercased().contains(trimmed)
            || ($0.categoryName?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            handleAndSummary
                .gesture(dragGesture)

            if state != .collapsed {
                // [2026-04-29] chips 영역과 콘텐츠 영역을 같은 시트의 섹션으로 시각화
                Divider()
                    .background(DesignTokens.Glass.borderColorLight.opacity(0.3))
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, 8)

                if state == .expanded {
                    expandedContent
                } else {
                    peekContent
                }
            }
        }
        .clipped()
        .onChange(of: filter) { _, _ in sheetPage = 0 }
        .onChange(of: searchText) { _, _ in sheetPage = 0 }
    }

    // MARK: - Handle + Summary

    private var handleAndSummary: some View {
        // [2026-04-30] 핸들·chips·chevron 한 줄 정렬로 시트 헤더 통합.
        // 기존: 핸들이 별도 행으로 떠 있어 시트 외부에 있는 것처럼 보였음.
        VStack(spacing: 0) {
            // 미니 핸들 — 작고 미세하게, 시트 상단에 흡수
            Capsule()
                .fill(DesignTokens.Colors.textTertiary.opacity(0.35))
                .frame(width: 36, height: 3)
                .padding(.top, 6)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                summaryChip(icon: "antenna.radiowaves.left.and.right", text: "LIVE \(liveChannels.count)", tint: DesignTokens.Colors.live)
                summaryChip(icon: "rectangle.3.group", text: "Queue \(queueIds.count)", tint: DesignTokens.Colors.accentOrange)
                summaryChip(icon: "play.rectangle", text: "세션 \(multiSessionCount)/\(multiSessionMax)", tint: DesignTokens.Colors.chzzkGreen)
                Spacer(minLength: 0)
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        state = state.next
                    }
                } label: {
                    Image(systemName: chevronIcon)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(
                            Capsule()
                                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.85))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.4), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help(state == .expanded ? "접기" : "펼치기")
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, state == .collapsed ? 8 : 6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // collapsed → peek 만 자동. peek/expanded 는 chevron 으로 명시 토글.
            if state == .collapsed {
                withAnimation(DesignTokens.Animation.snappy) { state = .peek }
            }
        }
    }

    private var chevronIcon: String {
        switch state {
        case .collapsed: return "chevron.up"
        case .peek: return "chevron.up"
        case .expanded: return "chevron.down"
        }
    }

    private func summaryChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
    }

    // MARK: - Peek

    private var peekContent: some View {
        // [2026-04-30] peek 콘텐츠 정밀화 — spotlight 제거, 단일 horizontal rail 만 표시.
        // 기존: spotlight + rail 병기로 시트 하단이 잘렸음 (peek 높이 < 두 카드 합계).
        // 신규: 12개 미니 카드로 압축 노출, 더 보기는 expanded 로 전환.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(liveChannels.prefix(12), id: \.channelId) { ch in
                    miniLiveCard(ch)
                }
                if liveChannels.count > 12 {
                    moreCardButton(remaining: liveChannels.count - 12)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, 10)
        }
    }

    /// peek rail 끝 — 더 많은 채널이 있을 때 expanded 로 안내하는 카드.
    private func moreCardButton(remaining: Int) -> some View {
        Button {
            withAnimation(DesignTokens.Animation.snappy) { state = .expanded }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "chevron.right.2")
                    .font(DesignTokens.Typography.custom(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("+\(remaining)")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("전체 보기")
                    .font(DesignTokens.Typography.custom(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(width: 96, height: 132)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.30), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 8) {
            // 검색 + 필터
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    TextField("팔로잉 검색", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(DesignTokens.Colors.surfaceBase.opacity(0.85)))

                ForEach(FollowingSheetFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(DesignTokens.Animation.snappy) { filter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.icon)
                                .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                            Text(f.title)
                                .font(DesignTokens.Typography.custom(size: 11, weight: filter == f ? .bold : .medium))
                        }
                        .foregroundStyle(filter == f ? .white : DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(filter == f ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surfaceBase.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                }

                Picker("표시", selection: $displayMode) {
                    ForEach(FollowingDisplayMode.allCases, id: \.self) { m in
                        Image(systemName: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)

            // 콘텐츠
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if displayMode == .spotlight, let first = pagedChannels.first ?? filteredChannels.first {
                        spotlightCard(first)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                    }

                    if displayMode != .dense {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                let railSource = displayMode == .spotlight ? Array(pagedChannels.dropFirst()) : pagedChannels
                                ForEach(railSource, id: \.channelId) { ch in
                                    miniLiveCard(ch)
                                }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.md)
                        }
                    }

                    if displayMode == .dense {
                        VStack(spacing: 4) {
                            ForEach(pagedChannels, id: \.channelId) { ch in
                                denseRow(ch)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    }

                    // 페이징 컨트롤
                    if totalSheetPages > 1 {
                        sheetPagingControl
                            .padding(.horizontal, DesignTokens.Spacing.md)
                    }

                    // Smart Queue
                    // [2026-04-28 P2] 큐가 비어 있어도 "추천으로 채우기" 액션은 항상 노출.
                    smartQueueSection
                        .padding(.horizontal, DesignTokens.Spacing.md)

                    Color.clear.frame(height: 12)
                }
            }
        }
    }

    // MARK: - Sheet Paging Control

    private var sheetPagingControl: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(DesignTokens.Animation.snappy) { sheetPage = max(0, sheetPage - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(sheetPage > 0 ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                    .frame(width: 28, height: 24)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceElevated.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .disabled(sheetPage == 0)

            Text("\(sheetPage + 1) / \(totalSheetPages)  (\(filteredChannels.count)개)")
                .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Button {
                withAnimation(DesignTokens.Animation.snappy) { sheetPage = min(totalSheetPages - 1, sheetPage + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(sheetPage < totalSheetPages - 1 ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                    .frame(width: 28, height: 24)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceElevated.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .disabled(sheetPage >= totalSheetPages - 1)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Cards

    private func spotlightCard(_ channel: LiveChannelItem) -> some View {
        Button {
            onOpenWatch(channel)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    if let url = channel.thumbnailUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                            default: DesignTokens.Colors.surfaceBase
                            }
                        }
                        .frame(width: 220, height: 124)
                        .clipped()
                    } else {
                        DesignTokens.Colors.surfaceBase.frame(width: 220, height: 124)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(DesignTokens.Colors.live).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.custom(size: 14, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    Text(channel.liveTitle)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Label(channel.formattedViewerCount, systemImage: "eye.fill")
                        if let cat = channel.categoryName {
                            Label(cat, systemImage: "tag.fill")
                        }
                    }
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        cardActionButton(icon: "play.fill", text: "보기", tint: DesignTokens.Colors.chzzkGreen) {
                            onOpenWatch(channel)
                        }
                        cardActionButton(icon: "plus", text: "+멀티", tint: DesignTokens.Colors.accentOrange) {
                            onAddMulti(channel)
                        }
                        cardActionButton(
                            icon: queueIds.contains(channel.channelId) ? "checkmark" : "tray.and.arrow.down",
                            text: queueIds.contains(channel.channelId) ? "Queue ✓" : "Queue",
                            tint: DesignTokens.Colors.accentBlue
                        ) {
                            onToggleQueue(channel.channelId)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .background(
                // [2026-04-30] 시트 배경 톤 조정에 맞춰 카드 배경 약화 —
                // 시트 컨테이너와의 이중 배경 충돌을 줄이고 카드는 가벼운 표면으로 변경.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.70))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.4), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardActionButton(icon: String, text: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 9.5, weight: .semibold))
                Text(text)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
    }

    private func miniLiveCard(_ channel: LiveChannelItem) -> some View {
        Button {
            onOpenWatch(channel)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if let url = channel.thumbnailUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                            default: DesignTokens.Colors.surfaceBase
                            }
                        }
                        .frame(width: 168, height: 94)
                        .clipped()
                    } else {
                        DesignTokens.Colors.surfaceBase.frame(width: 168, height: 94)
                    }
                    if channel.isLive {
                        HStack(spacing: 3) {
                            Circle().fill(DesignTokens.Colors.live).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(DesignTokens.Typography.custom(size: 8.5, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 6) {
                    Text(channel.channelName)
                        .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        onAddMulti(channel)
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.accentOrange)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(DesignTokens.Colors.accentOrange.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("멀티에 추가")
                }

                Text("\(channel.formattedViewerCount) · \(channel.categoryName ?? "—")")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                if channel.isLive && !channel.liveTitle.isEmpty {
                    Text(channel.liveTitle)
                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.75))
                        .lineLimit(1)
                        .frame(width: 152, alignment: .leading)
                }
            }
            .frame(width: 168, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceBase.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))
        .contextMenu {
            Button("시청 모드로 열기") { onOpenWatch(channel) }
            Button("멀티에 추가") { onAddMulti(channel) }
            Button(queueIds.contains(channel.channelId) ? "Queue에서 제거" : "Smart Queue 담기") {
                onToggleQueue(channel.channelId)
            }
            Divider()
            Button("채널 이름 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.channelName, forType: .string)
            }
        }
    }

    private func denseRow(_ channel: LiveChannelItem) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if let s = channel.channelImageUrl, let u = URL(string: s) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                        default: DesignTokens.Colors.surfaceBase
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                } else {
                    Circle().fill(DesignTokens.Colors.surfaceBase).frame(width: 28, height: 28)
                }
                if channel.isLive {
                    Circle()
                        .strokeBorder(DesignTokens.Colors.live, lineWidth: 1.2)
                        .frame(width: 30, height: 30)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(channel.channelName)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Text(channel.liveTitle.isEmpty ? "(오프라인)" : channel.liveTitle)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let cat = channel.categoryName {
                Text(cat)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(DesignTokens.Colors.surfaceBase.opacity(0.6)))
            }

            if channel.isLive {
                Text(channel.formattedViewerCount)
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 4) {
                Button { onOpenWatch(channel) } label: {
                    Image(systemName: "play.fill")
                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DesignTokens.Colors.chzzkGreen.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("시청")

                Button { onAddMulti(channel) } label: {
                    Image(systemName: "plus")
                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DesignTokens.Colors.accentOrange.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("+멀티")

                Button { onToggleQueue(channel.channelId) } label: {
                    Image(systemName: queueIds.contains(channel.channelId) ? "checkmark" : "tray.and.arrow.down")
                        .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DesignTokens.Colors.accentBlue.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Smart Queue")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredChannelId == channel.channelId
                    ? DesignTokens.Colors.surfaceElevated.opacity(0.65)
                    : DesignTokens.Colors.surfaceBase.opacity(0.45))
        )
        .onHover { isHovering in
            hoveredChannelId = isHovering ? channel.channelId : nil
        }
    }

    // MARK: - Smart Queue

    private var smartQueueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                Text("Smart Queue")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("\(queueIds.count)개 후보")
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer(minLength: 0)
                Button("추천으로 채우기") { onAutoFillQueue() }
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                    .buttonStyle(.plain)
                    .help("최근 시청·즐겨찾기·시청자 수를 종합한 추천 알고리즘으로 큐를 채웁니다")
                Button("일괄 추가") { onFlushQueue() }
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .buttonStyle(.plain)
                Button("비우기") { onClearQueue() }
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if queueIds.isEmpty {
                        Text("추천으로 채우기를 눌러 큐를 자동 생성하거나, 카드의 컨텍스트 메뉴에서 직접 담아보세요.")
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    ForEach(queueIds, id: \.self) { id in
                        let name = (liveChannels.first { $0.channelId == id }?.channelName)
                            ?? (offlineChannels.first { $0.channelId == id }?.channelName)
                            ?? id
                        HStack(spacing: 4) {
                            Text(name)
                                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Button { onToggleQueue(id) } label: {
                                Image(systemName: "xmark")
                                    .font(DesignTokens.Typography.custom(size: 8, weight: .bold))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(DesignTokens.Colors.accentOrange.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.28), lineWidth: 0.5))
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(0.4))
        )
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragOffset) { v, s, _ in s = v.translation.height }
            .onEnded { value in
                let dy = value.translation.height
                if dy < -50 {
                    withAnimation(DesignTokens.Animation.snappy) {
                        if state == .collapsed { state = .peek }
                        else if state == .peek { state = .expanded }
                    }
                } else if dy > 50 {
                    withAnimation(DesignTokens.Animation.snappy) {
                        if state == .expanded { state = .peek }
                        else if state == .peek { state = .collapsed }
                    }
                }
            }
    }
}
