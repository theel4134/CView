// MARK: - HomeView.swift
// CViewApp - 홈 대시보드 (Minimal Monochrome)
// 통계 카드 + Swift Charts + 인기 채널 그리드

import SwiftUI
import CViewCore
import CViewPlayer
import CViewUI

// MARK: - Home Dashboard View

struct HomeView: View {
    
    @Bindable var viewModel: HomeViewModel
    @Environment(AppRouter.self) var router
    @Environment(AppState.self) private var appState
    
    /// 캐시 시각 기준 인사말 (뷰 갱신 시에만 재계산, Date() 직접 호출 방지)
    var greeting: String {
        let referenceDate = viewModel.liveChannelsCachedAt ?? Date()
        let hour = Calendar.current.component(.hour, from: referenceDate)
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "좋은 아침이에요"
        case 12..<18: timeGreeting = "좋은 오후에요"
        case 18..<22: timeGreeting = "좋은 저녁이에요"
        default: timeGreeting = "좋은 밤이에요"
        }
        if let nickname = appState.userNickname, !nickname.isEmpty {
            return "\(nickname) 님, \(timeGreeting)"
        }
        return timeGreeting
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // 1. Header
                dashboardHeader

                // 2. Stat Cards (skeleton when loading with no data)
                if viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty && viewModel.liveChannels.isEmpty {
                    skeletonStatCards
                } else {
                    statCardsGrid
                }

                // 3. Charts (skeleton when loading)
                if viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty {
                    skeletonChartsSection
                } else {
                    chartsSection
                }

                // 4. Analytics (카테고리 분포 + 시청자 분포)
                if !(viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty) {
                    analyticsSection
                }

                // 5. Metrics Server Section
                if viewModel.isMetricsServerOnline {
                    metricsServerSection
                }

                // 6. Personal Stats (Following)
                if appState.isLoggedIn {
                    personalStatsSection
                }

                // 7. Top Channels Grid
                topChannelsSection
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .contentBackground()
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }

    // MARK: - Prefetch Helper

    /// 채널 카드 호버 시 HLS 매니페스트 프리페치를 비동기로 트리거
    func triggerPrefetch(channelId: String) {
        if let service = appState.hlsPrefetchService {
            Task { await service.prefetch(channelId: channelId) }
        }
    }
    
    // MARK: - 3. Charts Section

    var chartsSection: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            ViewerTrendChart(history: viewModel.viewerHistory)
                .frame(maxWidth: .infinity)

            CategoryBarChart(categories: viewModel.topCategories)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers
    
    /// macOS 네이티브 섹션 헤더
    func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if let subtitle = subtitle {
                Text("·  \(subtitle)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    func formatLargeNumber(_ num: Int) -> String {
        if num >= 10_000 {
            return String(format: "%.1f만", Double(num) / 10_000.0)
        } else if num >= 1_000 {
            return String(format: "%.1f천", Double(num) / 1_000.0)
        }
        return "\(num)"
    }
}
