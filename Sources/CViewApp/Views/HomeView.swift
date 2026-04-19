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
    @Environment(AppState.self) var appState

    /// 자동 업데이트 시트 표시 여부
    @State var showUpdateSheet = false
    
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
            // 앱 실행 후 한 번 백그라운드로 업데이트 확인 (24h 간격)
            scheduleSilentUpdateCheck()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .sheet(isPresented: $showUpdateSheet) {
            UpdateSheetView(service: appState.updateService)
        }
    }

    // MARK: - Silent Update Check

    /// 최근 24시간 내 확인한 적 없으면 조용히 업데이트 조회 (실패해도 UI 표시 안 함)
    func scheduleSilentUpdateCheck() {
        let service = appState.updateService
        if let last = service.lastCheckedAt, Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s 지연
            await service.checkForUpdates(silent: true)
            // 새 버전이 발견되면 자동으로 시트 열기
            if case .updateAvailable = service.status {
                showUpdateSheet = true
            }
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
        // 좁은 폭에서는 세로, 넓은 폭에서는 가로 2열
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                ViewerTrendChart(history: viewModel.viewerHistory)
                    .frame(maxWidth: .infinity)

                CategoryBarChart(categories: viewModel.topCategories)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ViewerTrendChart(history: viewModel.viewerHistory)
                CategoryBarChart(categories: viewModel.topCategories)
            }
        }
    }

    // MARK: - Helpers
    
    /// macOS 네이티브 섹션 헤더
    func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            if let subtitle = subtitle {
                Text("·  \(subtitle)")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
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

    /// 캐시가 아직 없을 때 헤더에 표시할 오늘 날짜 라벨 (정적 1회 캡처 — body 평가 시 Date() 재생성 방지)
    static let todayLabel: String = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("yyyy M d EEEE")
        return fmt.string(from: Date())
    }()

    var todayLabel: String { HomeView.todayLabel }
}
