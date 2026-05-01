// MARK: - CategoryBrowseView.swift
// CViewApp - 카테고리 목록 → 채널 목록 탐색
//
// 2026-04-23 정밀 개편:
//  - C1/H1: ContentState 머신으로 분기 flatten + 로딩/부분/완료/빈/에러 명시 분리
//  - C2: 새로고침 시 allStatChannels wipe 제거 (loadAllStatsChannels 내부에서 success 시 replace)
//  - C3: hashValue → FNV-1a 결정적 해시 (재실행 시 색/아이콘 불변)
//  - C4: Dictionary grouping 후 (count DESC, name ASC) tie-breaker
//  - C5: .task → .task(id:) + loadAllStatsChannelsIfStale 가드
//  - C6: statsLoadError 배너 + 재시도 버튼
//  - H2: 타입 필터 하드코딩 → 데이터에서 동적 파생
//  - H3: "기타" → "분류 없음" (categoryName nil 표시 명확화)
//  - H4: strokeBorder lineWidth 애니메이션 제거 (GPU: CAShapeLayer re-tessellation 방지)
//  - H5: onGeometryChange 100px 단위로 quantize
//  - H6: 필터링 computed → memoize
//  - H7/M9: 채널 카드 Button 래핑 + accessibilityLabel + PressScaleButtonStyle
//  - H8: 새로고침 버튼 회전 TimelineView 기반 continuous
//  - H9: 뒤로가기 시 검색+타입필터 동시 리셋
//  - H10: 새로고침 중복 탭 방지 (isLoadingStats 가드)
//  - H11: 외부 LazyVStack → VStack (lazy 중첩 제거)
//  - M1: previewChannels 사용 안 함 제거
//  - M6: empty icon → square.grid.2x2.slash
//  - M11: PressScaleButtonStyle 전면 적용 (FollowingView 일관성)
//  - M12: statsLoadingBanner overlay(.top) 배치로 레이아웃 shift 제거
//
// 2026-04-23 Phase 3/4 확장:
//  - M3: 글로벌 채널 검색 모드 (카테고리 교차 검색, 검색창 포커스 시 자동 진입)
//  - M4: 정렬 옵션 (카테고리: 라이브수/가나다, 채널: 시청자/이름/제목)
//  - M5: 즐겨찾기/고정 카테고리 (@AppStorage, 상단 섹션, 컨텍스트 메뉴 토글)
//  - M10: 키보드 네비게이션 (ESC 뒤로가기, / 검색 포커스, ⌘F 검색, ⌘R 새로고침, Cmd+1–9)
//  - L5: #Preview 추가
//  - CategoryHash → StableHash (CViewCore 이동, 테스트 가능)

import CViewCore
import CViewUI
import SwiftUI

// MARK: - ContentState (C1/H1 flatten)

private enum CategoryContentState: Equatable {
    case initialLoading  // 최초 liveChannels 페이지 로드 중
    case partial  // liveChannels 보임, 전체 통계 수집 중
    case ready  // 전체 통계 반영 완료
    case empty  // 라이브 없음
    case error(String)  // 수집 실패
}

// MARK: - Sort Options (M4)

enum CategorySortMode: String, CaseIterable, Identifiable {
    case liveCountDesc  // 라이브 수 많은 순 (기본)
    case nameAsc  // 가나다
    var id: String { rawValue }
    var label: String {
        switch self {
        case .liveCountDesc: return "라이브 수"
        case .nameAsc: return "이름순"
        }
    }
    var icon: String {
        switch self {
        case .liveCountDesc: return "chart.bar.fill"
        case .nameAsc: return "textformat.abc"
        }
    }
}

// [Trend Atlas 2026-04-28] 카테고리 보기 모드 (실험 플래그 활성 시 노출).
enum CategoryViewMode: String, CaseIterable, Identifiable {
    case grid  // Command Grid (기본)
    case split  // Split Explorer (수동 강제)
    case trend  // Trend Atlas (보조 발견 모드)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: return "그리드"
        case .split: return "분할"
        case .trend: return "트렌드"
        }
    }
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .split: return "rectangle.split.2x1"
        case .trend: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum ChannelSortMode: String, CaseIterable, Identifiable {
    case viewersDesc  // 시청자 많은 순 (기본)
    case viewersAsc
    case nameAsc  // 채널명 가나다
    case titleAsc  // 방송 제목 가나다
    var id: String { rawValue }
    var label: String {
        switch self {
        case .viewersDesc: return "시청자 많은 순"
        case .viewersAsc: return "시청자 적은 순"
        case .nameAsc: return "채널명"
        case .titleAsc: return "방송 제목"
        }
    }
    var icon: String {
        switch self {
        case .viewersDesc: return "person.3.sequence.fill"
        case .viewersAsc: return "person.2"
        case .nameAsc: return "textformat.abc"
        case .titleAsc: return "text.alignleft"
        }
    }
}

// MARK: - Category Browse View

struct CategoryBrowseView: View {

    @Bindable var viewModel: HomeViewModel
    @Environment(AppRouter.self) private var router

    @State private var selectedCategory: String? = nil
    @State private var channelSearchText: String = ""
    @State private var isRefreshing: Bool = false
    @State private var contentWidth: CGFloat = 900
    @State private var selectedTypeFilter: String? = nil  // nil=전체
    // [Fix C-1] 폭 변경 debounce — 빠른 리사이즈 중 레이아웃 재계산 억제
    @State private var widthDebounceTask: Task<Void, Never>?

    // MARK: - Paging
    /// 전체 섹션의 현재 페이지 (0-based)
    @State private var categoryGridPage: Int = 0
    /// 페이지당 카테고리 수
    private static let categoriesPerPage: Int = 48

    /// 카테고리 내 채널 목록 현재 페이지 (0-based) — channelListView 전용
    @State private var channelListPage: Int = 0
    /// Split Explorer 우측 채널 그리드 현재 페이지 (0-based)
    @State private var splitChannelPage: Int = 0
    /// 채널 목록 페이지당 채널 수
    private static let channelsPerPage: Int = 48

    // [Split Explorer 2026-04-28] 넓은 창에서 rail+grid 동시 보기
    // selectedCategory(전체 화면 전환)와는 별도. drill-through 없이 선택만 갱신.
    @State private var splitSelectedCategory: String? = nil

    // [M3] 글로벌 검색 (카테고리 단계에서도 채널명/제목 교차 검색)
    @State private var globalSearchText: String = ""
    @FocusState private var isGlobalSearchFocused: Bool
    @FocusState private var isChannelSearchFocused: Bool

    // [M4] 정렬
    @AppStorage("category.sortMode")
    private var categorySortRaw: String = CategorySortMode.liveCountDesc.rawValue
    @AppStorage("category.channelSortMode")
    private var channelSortRaw: String = ChannelSortMode.viewersDesc.rawValue

    // [Trend Atlas 2026-04-28] 실험 플래그 — 켜진 사용자만 보기 옵션(그리드/분할/트렌드) 노출
    @AppStorage("category.experimentalTrendMode")
    private var prefExperimentalTrendMode: Bool = false
    @AppStorage("category.viewMode")
    private var viewModeRaw: String = CategoryViewMode.grid.rawValue
    private var viewMode: CategoryViewMode {
        CategoryViewMode(rawValue: viewModeRaw) ?? .grid
    }
    private var categorySort: CategorySortMode {
        CategorySortMode(rawValue: categorySortRaw) ?? .liveCountDesc
    }
    private var channelSort: ChannelSortMode {
        ChannelSortMode(rawValue: channelSortRaw) ?? .viewersDesc
    }

    // [M5] 즐겨찾기/고정 카테고리 — @AppStorage(JSON 문자열)
    @AppStorage("category.pinnedCategories")
    private var pinnedCategoriesRaw: String = "[]"
    private var pinnedCategories: Set<String> {
        guard let data = pinnedCategoriesRaw.data(using: .utf8),
            let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }
    private func togglePin(_ category: String) {
        var set = pinnedCategories
        if set.contains(category) { set.remove(category) } else { set.insert(category) }
        let arr = Array(set).sorted()
        if let data = try? JSONEncoder().encode(arr),
            let s = String(data: data, encoding: .utf8)
        {
            pinnedCategoriesRaw = s
        }
    }

    // [H5] 너비 quantize 상수 (100px 단위) — 칼럼 배열 재계산 억제
    private static let widthQuantizeStep: CGFloat = 100

    // [Split Explorer 2026-04-28] 이 너비 이상일 때 rail+grid 분할 모드 진입
    private static let splitWidthThreshold: CGFloat = 1180
    private static let splitRailWidth: CGFloat = 232

    // [H3] 카테고리명 폴백
    private static let uncategorizedLabel = "분류 없음"

    private var channelGridColumns: [GridItem] {
        let cardWidth: CGFloat = 240
        let spacing: CGFloat = 12
        let available = max(300, contentWidth - 32)
        let count = max(2, min(6, Int(available / (cardWidth + spacing))))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    private var gridColumns: [GridItem] {
        // [Lightweight 2026-04-28] 카드 width 160 → 144 (높이 118에 맞춰 비율 조정 + 한 줄에 더 많이)
        let cardWidth: CGFloat = 144
        let spacing: CGFloat = 12
        let available = max(300, contentWidth - 32)
        let count = max(3, min(8, Int(available / (cardWidth + spacing))))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// 현재 소스: 전체 수집 완료 시 allStatChannels, 아직이면 liveChannels
    private var sourceChannels: [LiveChannelItem] {
        viewModel.categoryChannels
    }

    /// [H2] 데이터에서 동적으로 파생한 타입 필터 목록
    private var availableTypeFilters: [(label: String, icon: String, value: String?)] {
        // 고정 order: 전체 → 게임 → 스포츠 → 기타 → 그 외 발견된 type
        var result: [(String, String, String?)] = [("전체", "square.grid.2x2", nil)]
        let knownTypes: [(String, String, String)] = [
            ("GAME", "게임", "gamecontroller.fill"),
            ("SPORTS", "스포츠", "sportscourt.fill"),
            ("ETC", "기타", "ellipsis.circle.fill"),
        ]
        let presentTypes = Set(sourceChannels.compactMap { $0.categoryType })
        for (raw, label, icon) in knownTypes where presentTypes.contains(raw) {
            result.append((label, icon, raw))
        }
        // 알려지지 않은 타입은 그대로 노출 (i18n 미적용이지만 누락 방지)
        for unknown in presentTypes.subtracting(Set(knownTypes.map { $0.0 })).sorted() {
            result.append((unknown, "tag.fill", unknown))
        }
        return result
    }

    private var categorizedChannels: [(category: String, channels: [LiveChannelItem])] {
        let filtered =
            selectedTypeFilter == nil
            ? sourceChannels
            : sourceChannels.filter { $0.categoryType == selectedTypeFilter }
        let grouped = Dictionary(grouping: filtered) {
            $0.categoryName ?? Self.uncategorizedLabel
        }
        let mapped = grouped.map { (category: $0.key, channels: $0.value) }
        // [C4] 결정적 정렬 + [M4] 사용자 정렬 옵션 반영 (count 동률은 name ASC)
        switch categorySort {
        case .liveCountDesc:
            return mapped.sorted { lhs, rhs in
                if lhs.channels.count != rhs.channels.count {
                    return lhs.channels.count > rhs.channels.count
                }
                return lhs.category < rhs.category
            }
        case .nameAsc:
            return mapped.sorted { $0.category < $1.category }
        }
    }

    /// [M5] 고정 카테고리 (상단 섹션) — categorizedChannels 에서 분리
    private var pinnedGroups: [(category: String, channels: [LiveChannelItem])] {
        let pins = pinnedCategories
        guard !pins.isEmpty else { return [] }
        return categorizedChannels.filter { pins.contains($0.category) }
    }

    private var unpinnedGroups: [(category: String, channels: [LiveChannelItem])] {
        let pins = pinnedCategories
        guard !pins.isEmpty else { return categorizedChannels }
        return categorizedChannels.filter { !pins.contains($0.category) }
    }

    /// [Lightweight 2026-04-28] 인기 카테고리 — 고정 제외 상위 N개 (liveCount 내림차순).
    /// 고정된 상자가 있고 unpinned 가 충분히 많을 때만 독립 섹션으로 제공.
    /// 인기 카드에는 viewer count 힌트도 녹이고, 전체 그리드는 dense tile 로 단순화.
    private var popularGroups: [(category: String, channels: [LiveChannelItem])] {
        // 고정이 하나도 없으면 인기 섹션도 생략 (상위는 자연스럽게 최상단 grid 에 드러남).
        guard !pinnedCategories.isEmpty else { return [] }
        // unpinned 가 최소 6개 이상일 때만 활성화 (입적은 총 리스트로 충분).
        guard unpinnedGroups.count >= 6 else { return [] }
        // liveCount 내림차순 상위 4개 (이미 categorizedChannels.sort 기본값이 내림차순 일 때에만 의미 있음).
        guard categorySort == .liveCountDesc else { return [] }
        return Array(unpinnedGroups.prefix(4))
    }

    /// 인기 섹션을 제외한 나머지 전체 섹션.
    private var remainingGroups: [(category: String, channels: [LiveChannelItem])] {
        if popularGroups.isEmpty { return unpinnedGroups }
        let popularKeys = Set(popularGroups.map(\.category))
        return unpinnedGroups.filter { !popularKeys.contains($0.category) }
    }

    // MARK: - Paging helpers

    /// 전체 페이지 수 (remainingGroups 기준)
    private var categoryPageCount: Int {
        max(1, Int(ceil(Double(remainingGroups.count) / Double(Self.categoriesPerPage))))
    }

    /// 현재 페이지에 해당하는 remainingGroups slice
    private var pagedRemainingGroups: [(category: String, channels: [LiveChannelItem])] {
        let start = categoryGridPage * Self.categoriesPerPage
        let end = min(start + Self.categoriesPerPage, remainingGroups.count)
        guard start < end else { return [] }
        return Array(remainingGroups[start..<end])
    }

    /// 페이지 리셋 — 필터/정렬 변경 시 호출
    private func resetPage() {
        guard categoryGridPage != 0 else { return }
        categoryGridPage = 0
    }

    // MARK: - Channel list paging helpers

    private var channelPageCount: Int {
        max(1, Int(ceil(Double(channelsInCategory.count) / Double(Self.channelsPerPage))))
    }

    private var pagedChannelsInCategory: [LiveChannelItem] {
        let start = channelListPage * Self.channelsPerPage
        let end = min(start + Self.channelsPerPage, channelsInCategory.count)
        guard start < end else { return [] }
        return Array(channelsInCategory[start..<end])
    }

    private func resetChannelPage() {
        guard channelListPage != 0 else { return }
        channelListPage = 0
    }

    /// [M3] 글로벌 검색 결과 (카테고리 단계에서 전체 채널 교차 검색)
    private var globalSearchResults: [LiveChannelItem] {
        let q = globalSearchText.lowercased()
        guard !q.isEmpty else { return [] }
        return
            sourceChannels
            .filter {
                $0.channelName.lowercased().contains(q) || $0.liveTitle.lowercased().contains(q)
                    || ($0.categoryName?.lowercased().contains(q) ?? false)
            }
            .sorted { $0.viewerCount > $1.viewerCount }  // 글로벌 검색은 시청자 많은 순 고정
    }

    private var channelsInCategory: [LiveChannelItem] {
        guard let cat = selectedCategory else { return [] }
        let base = sourceChannels.filter {
            ($0.categoryName ?? Self.uncategorizedLabel) == cat
        }
        let searched: [LiveChannelItem]
        if channelSearchText.isEmpty {
            searched = base
        } else {
            let q = channelSearchText.lowercased()
            searched = base.filter {
                $0.channelName.lowercased().contains(q) || $0.liveTitle.lowercased().contains(q)
            }
        }
        // [M4] 채널 정렬 — 동률 시 channelId ASC 로 결정성 확보
        return sortChannels(searched, by: channelSort)
    }

    private func sortChannels(_ list: [LiveChannelItem], by mode: ChannelSortMode)
        -> [LiveChannelItem]
    {
        switch mode {
        case .viewersDesc:
            return list.sorted { lhs, rhs in
                if lhs.viewerCount != rhs.viewerCount { return lhs.viewerCount > rhs.viewerCount }
                return lhs.channelId < rhs.channelId
            }
        case .viewersAsc:
            return list.sorted { lhs, rhs in
                if lhs.viewerCount != rhs.viewerCount { return lhs.viewerCount < rhs.viewerCount }
                return lhs.channelId < rhs.channelId
            }
        case .nameAsc:
            return list.sorted { lhs, rhs in
                if lhs.channelName != rhs.channelName { return lhs.channelName < rhs.channelName }
                return lhs.channelId < rhs.channelId
            }
        case .titleAsc:
            return list.sorted { lhs, rhs in
                if lhs.liveTitle != rhs.liveTitle { return lhs.liveTitle < rhs.liveTitle }
                return lhs.channelId < rhs.channelId
            }
        }
    }

    /// [C1/H1] 현재 컨텐츠 상태 판정
    private var contentState: CategoryContentState {
        if let err = viewModel.statsLoadError,
            viewModel.allStatChannels.isEmpty, viewModel.liveChannels.isEmpty
        {
            return .error(err)
        }
        if viewModel.isLoading && viewModel.liveChannels.isEmpty {
            return .initialLoading
        }
        if viewModel.isLoadingStats && viewModel.allStatChannels.isEmpty {
            return categorizedChannels.isEmpty ? .initialLoading : .partial
        }
        if categorizedChannels.isEmpty { return .empty }
        if viewModel.isLoadingStats { return .partial }
        return .ready
    }

    var body: some View {
        VStack(spacing: 0) {
            // [Top chrome 2026-05-01] hiddenTitleBar + .ignoresSafeArea(top) 환경에서
            // 상단 ~28pt 가 macOS 트래픽 라이트/드래그 영역과 겹쳐 카테고리 헤더의
            // 아이콘·타이틀 위로 빨/노/초 신호등이 올라오는 문제 해결.
            // (SettingsWorkspace, FollowingView+Header 와 동일한 보정.)
            Color.clear
                .frame(height: 28)
            ZStack {
                if let category = selectedCategory {
                    channelListView(for: category)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if effectiveViewMode == .trend {
                    trendAtlasView
                        .transition(.opacity)
                } else if effectiveViewMode == .split {
                    splitExplorerView
                        .transition(.opacity)
                } else {
                    categoryGridView
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(DesignTokens.Animation.contentTransition, value: selectedCategory)
        .animation(DesignTokens.Animation.contentTransition, value: effectiveViewMode)
        .contentBackground()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // [H5] 100px 단위 quantize — 리사이즈 중 레이아웃 재계산 폭발 억제
            // [Fix C-1] 200ms debounce — split threshold(1180px) 근방에서 깜빡임 방지
            let quantized = (width / Self.widthQuantizeStep).rounded() * Self.widthQuantizeStep
            guard abs(contentWidth - quantized) >= Self.widthQuantizeStep else { return }
            widthDebounceTask?.cancel()
            widthDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                contentWidth = quantized
            }
        }
        // [C5] .task(id:) — 뷰 재등장 때마다 수집 트리거되지 않음
        .task(id: "category-browse-initial") {
            if viewModel.liveChannels.isEmpty {
                await viewModel.loadLiveChannels()
            }
            await viewModel.loadAllStatsChannelsIfStale()
        }
        // [M10] 키보드 단축키
        .onKeyPress(.escape) {
            if selectedCategory != nil {
                withAnimation(DesignTokens.Animation.contentTransition) {
                    selectedCategory = nil
                    channelSearchText = ""
                }
                return .handled
            }
            if !globalSearchText.isEmpty {
                globalSearchText = ""
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: ["/"]) { _ in
            if selectedCategory == nil {
                isGlobalSearchFocused = true
            } else {
                isChannelSearchFocused = true
            }
            return .handled
        }
    }

    // MARK: - 카테고리 그리드

    // [2026-04-23] 상단 헤더 + 글로벌 검색을 ScrollView 밖으로 분리하여 스크롤 시 고정.
    //              타입 필터/섹션 헤더는 콘텐츠와 함께 스크롤 (자연스러운 계층).
    private var categoryGridView: some View {
        VStack(spacing: 0) {
            // === 스티키 영역 ===
            stickyCategoryGridHeader

            // === 스크롤 영역 ===
            if !globalSearchText.isEmpty {
                ScrollView {
                    globalSearchResultsView
                        .padding(.top, DesignTokens.Spacing.sm)
                }
            } else {
                switch contentState {
                case .initialLoading:
                    ScrollView { loadingPlaceholder }
                case .empty:
                    ScrollView { emptyState("라이브 중인 카테고리가 없습니다") }
                case .error(let msg):
                    ScrollView { errorState(message: msg) }
                case .partial, .ready:
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 0).id("categoryGridTop")
                                categoryTypeFilter
                                    .padding(.horizontal, DesignTokens.Spacing.md)
                                    .padding(.top, DesignTokens.Spacing.sm)
                                    .padding(.bottom, DesignTokens.Spacing.sm)

                                if !pinnedGroups.isEmpty {
                                    pinnedSectionHeader
                                    categoryGrid(groups: pinnedGroups)
                                        .padding(.bottom, DesignTokens.Spacing.lg)
                                    if !popularGroups.isEmpty {
                                        popularSectionHeader
                                        categoryGrid(groups: popularGroups)
                                            .padding(.bottom, DesignTokens.Spacing.lg)
                                    }
                                    allSectionHeader
                                }
                                categoryGrid(groups: pagedRemainingGroups)

                                // MARK: 페이징 바
                                if categoryPageCount > 1 {
                                    categoryPagingBar
                                        .padding(.top, DesignTokens.Spacing.lg)
                                        .padding(.bottom, DesignTokens.Spacing.xl)
                                }
                            }
                            .animation(DesignTokens.Animation.smooth, value: pinnedCategoriesRaw)
                        }
                        // 페이지 전환 시 최상단 복귀
                        .onChange(of: categoryGridPage) { _, _ in
                            withAnimation(nil) { proxy.scrollTo("categoryGridTop", anchor: .top) }
                        }
                        // 필터·정렬 변경 시 1페이지로 리셋
                        .onChange(of: selectedTypeFilter) { _, _ in resetPage() }
                        .onChange(of: categorySortRaw) { _, _ in resetPage() }
                        .onChange(of: globalSearchText) { _, _ in resetPage() }
                    }
                }
            }
        }
    }

    // MARK: - Split Explorer (width >= 1180)
    /// (실험 플래그가 켜져 있을 때는 사용자가 viewMode 로 직접 강제 가능 → effectiveViewMode 참조.)
    private var isSplitMode: Bool {
        contentWidth >= Self.splitWidthThreshold && globalSearchText.isEmpty
    }

    /// 글로벌 검색 / 좁은 창 / 빈 데이터 조건을 반영해 실제 렌더에 사용할 view mode 를 결정.
    private var effectiveViewMode: CategoryViewMode {
        if !globalSearchText.isEmpty { return .grid }
        // 실험 플래그 OFF → 기존 동작: 넓은 창 자동 split, 그 외 grid.
        if !prefExperimentalTrendMode {
            return isSplitMode ? .split : .grid
        }
        // 실험 플래그 ON → 사용자가 고른 viewMode 사용. split 은 너비 부족 시 grid fallback.
        switch viewMode {
        case .grid: return .grid
        case .trend: return .trend
        case .split: return contentWidth >= Self.splitWidthThreshold ? .split : .grid
        }
    }

    // MARK: - Trend Atlas (실험 플래그)

    /// [Trend Atlas 2026-04-28] 카테고리별 viewer total helper. 채널 viewer 합산.
    /// trend 데이터가 없으므로 rising delta 등 가짜 지표는 만들지 않고 live count + viewer total 만 사용.
    private func viewerTotal(_ channels: [LiveChannelItem]) -> Int {
        channels.reduce(0) { $0 + $1.viewerCount }
    }

    /// 카테고리 랭킹용 row 데이터 — 한 번만 만들어서 재사용 (sort 비용 억제).
    private var trendRanking: [(category: String, channels: [LiveChannelItem], viewerTotal: Int)] {
        categorizedChannels.map { ($0.category, $0.channels, viewerTotal($0.channels)) }
            .sorted { lhs, rhs in
                if lhs.channels.count != rhs.channels.count {
                    return lhs.channels.count > rhs.channels.count
                }
                return lhs.viewerTotal > rhs.viewerTotal
            }
    }

    /// 상단 spotlight — 1위 카테고리.
    private var trendSpotlight: (category: String, channels: [LiveChannelItem], viewerTotal: Int)? {
        trendRanking.first
    }

    /// 보조 spotlight — 2~3위.
    private var trendSecondary: [(category: String, channels: [LiveChannelItem], viewerTotal: Int)]
    {
        Array(trendRanking.dropFirst().prefix(2))
    }

    /// 트렌드 메인 뷰.
    private var trendAtlasView: some View {
        VStack(spacing: 0) {
            stickyCategoryGridHeader
            switch contentState {
            case .initialLoading:
                ScrollView { loadingPlaceholder }
            case .empty:
                ScrollView { emptyState("라이브 중인 카테고리가 없습니다") }
            case .error(let msg):
                ScrollView { errorState(message: msg) }
            case .partial, .ready:
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        if let spotlight = trendSpotlight {
                            trendSpotlightSection(spotlight: spotlight, secondary: trendSecondary)
                        }
                        trendRankingSection
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                }
            }
        }
    }

    @ViewBuilder
    private func trendSpotlightSection(
        spotlight: (category: String, channels: [LiveChannelItem], viewerTotal: Int),
        secondary: [(category: String, channels: [LiveChannelItem], viewerTotal: Int)]
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("SPOTLIGHT")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .tracking(1.8)
            }

            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                TrendSpotlightCard(
                    rank: 1,
                    category: spotlight.category,
                    liveCount: spotlight.channels.count,
                    viewerTotal: spotlight.viewerTotal,
                    accentColor: accentColor(for: spotlight.category),
                    isPrimary: true
                ) {
                    withAnimation(DesignTokens.Animation.contentTransition) {
                        selectedCategory = spotlight.category
                    }
                }
                .equatable()
                .frame(maxWidth: .infinity)

                if !secondary.isEmpty {
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(Array(secondary.enumerated()), id: \.element.category) {
                            idx, item in
                            TrendSpotlightCard(
                                rank: idx + 2,
                                category: item.category,
                                liveCount: item.channels.count,
                                viewerTotal: item.viewerTotal,
                                accentColor: accentColor(for: item.category),
                                isPrimary: false
                            ) {
                                withAnimation(DesignTokens.Animation.contentTransition) {
                                    selectedCategory = item.category
                                }
                            }
                            .equatable()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var trendRankingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("RANKING")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .tracking(1.8)
                Spacer()
                Text("\(trendRanking.count)")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.bottom, DesignTokens.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(trendRanking.enumerated()), id: \.element.category) { idx, item in
                    TrendRankingRow(
                        rank: idx + 1,
                        category: item.category,
                        liveCount: item.channels.count,
                        viewerTotal: item.viewerTotal,
                        accentColor: accentColor(for: item.category)
                    ) {
                        withAnimation(DesignTokens.Animation.contentTransition) {
                            selectedCategory = item.category
                        }
                    }
                    .equatable()
                    if idx < trendRanking.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(
                DesignTokens.Colors.surfaceElevated.opacity(0.4),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }

    // MARK: - Split Explorer (width >= 1180)

    /// 분할 모드에서 우측 그리드에 표시할 채널 목록.
    private var splitChannels: [LiveChannelItem] {
        guard let cat = splitSelectedCategory else { return [] }
        let base = sourceChannels.filter {
            ($0.categoryName ?? Self.uncategorizedLabel) == cat
        }
        let q = channelSearchText.lowercased()
        let searched =
            q.isEmpty
            ? base
            : base.filter {
                $0.channelName.lowercased().contains(q) || $0.liveTitle.lowercased().contains(q)
            }
        return sortChannels(searched, by: channelSort)
    }

    private var splitChannelPageCount: Int {
        max(1, Int(ceil(Double(splitChannels.count) / Double(Self.channelsPerPage))))
    }

    private var pagedSplitChannels: [LiveChannelItem] {
        let start = splitChannelPage * Self.channelsPerPage
        let end = min(start + Self.channelsPerPage, splitChannels.count)
        guard start < end else { return [] }
        return Array(splitChannels[start..<end])
    }

    private func resetSplitChannelPage() {
        guard splitChannelPage != 0 else { return }
        splitChannelPage = 0
    }

    /// 분할 모드 우측 그리드 컬럼 — rail width 만큼 빼고 계산.
    private var splitChannelGridColumns: [GridItem] {
        let cardWidth: CGFloat = 240
        let spacing: CGFloat = 12
        let available = max(300, contentWidth - Self.splitRailWidth - 32)
        let count = max(2, min(6, Int(available / (cardWidth + spacing))))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// 분할 모드 메인 뷰. 좌측 카테고리 rail + 우측 채널 그리드.
    private var splitExplorerView: some View {
        VStack(spacing: 0) {
            stickyCategoryGridHeader
            switch contentState {
            case .initialLoading:
                ScrollView { loadingPlaceholder }
            case .empty:
                ScrollView { emptyState("라이브 중인 카테고리가 없습니다") }
            case .error(let msg):
                ScrollView { errorState(message: msg) }
            case .partial, .ready:
                HStack(alignment: .top, spacing: 0) {
                    splitCategoryRail
                        .frame(width: Self.splitRailWidth)
                    Divider()
                    splitChannelPane
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { autoPickSplitCategoryIfNeeded() }
        .onChange(of: pinnedCategoriesRaw) { _, _ in autoPickSplitCategoryIfNeeded() }
        .onChange(of: viewModel.categoryChannels.count) { _, _ in autoPickSplitCategoryIfNeeded() }
    }

    /// 좌측 카테고리 rail — dense row + 섹션 그룹.
    private var splitCategoryRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                if !pinnedGroups.isEmpty {
                    splitRailSection(
                        title: "고정", icon: "pin.fill", iconTint: DesignTokens.Colors.chzzkGreen,
                        groups: pinnedGroups)
                }
                if !popularGroups.isEmpty {
                    splitRailSection(
                        title: "인기", icon: "flame.fill", iconTint: DesignTokens.Colors.live,
                        groups: popularGroups)
                }
                splitRailSection(
                    title: "전체", icon: "square.grid.2x2",
                    iconTint: DesignTokens.Colors.textTertiary, groups: remainingGroups)
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }

    @ViewBuilder
    private func splitRailSection(
        title: String,
        icon: String,
        iconTint: Color,
        groups: [(category: String, channels: [LiveChannelItem])]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(iconTint)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("\(groups.count)")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, 4)

            ForEach(groups, id: \.category) { group in
                CategoryRailRow(
                    category: group.category,
                    liveCount: group.channels.count,
                    viewerTotal: group.channels.reduce(0) { $0 + $1.viewerCount },
                    isSelected: splitSelectedCategory == group.category,
                    isPinned: pinnedCategories.contains(group.category),
                    accentColor: accentColor(for: group.category)
                ) {
                    splitSelectedCategory = group.category
                    channelSearchText = ""
                }
                .equatable()
                .contextMenu {
                    Button {
                        togglePin(group.category)
                    } label: {
                        if pinnedCategories.contains(group.category) {
                            Label("고정 해제", systemImage: "pin.slash")
                        } else {
                            Label("카테고리 고정", systemImage: "pin")
                        }
                    }
                }
            }
        }
    }

    /// 우측 채널 그리드 + 헤더(카테고리명 + 검색 + 정렬).
    @ViewBuilder
    private var splitChannelPane: some View {
        if let cat = splitSelectedCategory {
            VStack(spacing: 0) {
                splitChannelHeader(category: cat)
                if splitChannels.isEmpty && !channelSearchText.isEmpty {
                    ScrollView { emptyState("'\(channelSearchText)' 검색 결과가 없습니다") }
                } else if splitChannels.isEmpty {
                    ScrollView { emptyState("\(cat) 카테고리 라이브가 없습니다") }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Color.clear.frame(height: 0).id("splitChannelTop")
                            LazyVGrid(columns: splitChannelGridColumns, spacing: 12) {
                                ForEach(pagedSplitChannels) { channel in
                                    CategoryChannelCard(channel: channel) {
                                        router.navigateToWatch(channelId: channel.channelId)
                                    }
                                    .equatable()
                                }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.sm)

                            if splitChannelPageCount > 1 {
                                channelPagingBar(
                                    currentPage: splitChannelPage,
                                    pageCount: splitChannelPageCount,
                                    total: splitChannels.count
                                ) { page in
                                    withAnimation(DesignTokens.Animation.snappy) {
                                        splitChannelPage = page
                                    }
                                }
                                .padding(.top, DesignTokens.Spacing.lg)
                                .padding(.bottom, DesignTokens.Spacing.xl)
                            } else {
                                Spacer().frame(height: DesignTokens.Spacing.xl)
                            }
                        }
                        // 페이지 전환 시 최상단 복귀
                        .onChange(of: splitChannelPage) { _, _ in
                            withAnimation(nil) { proxy.scrollTo("splitChannelTop", anchor: .top) }
                        }
                        .onChange(of: channelSearchText) { _, _ in resetSplitChannelPage() }
                        .onChange(of: channelSortRaw) { _, _ in resetSplitChannelPage() }
                        .onChange(of: splitSelectedCategory) { _, _ in resetSplitChannelPage() }
                    }
                }
            }
        } else {
            ScrollView { emptyState("왼쪽에서 카테고리를 선택해 주세요") }
        }
    }

    private func splitChannelHeader(category: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(accentColor(for: category))
                    .frame(width: 4, height: 22)
                Text(category)
                    .font(DesignTokens.Typography.custom(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("\(splitChannels.count)")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .contentTransition(.numericText())
                Spacer()
                channelSortMenu
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)

            channelSearchBar
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)

            Divider().opacity(0.4)
        }
        .background(DesignTokens.Colors.surfaceBase)
    }

    /// 분할 모드 진입 시 우측이 비어 있지 않도록 자동 선택.
    private func autoPickSplitCategoryIfNeeded() {
        guard isSplitMode, splitSelectedCategory == nil else { return }
        let firstAvailable =
            pinnedGroups.first?.category
            ?? popularGroups.first?.category
            ?? remainingGroups.first?.category
        guard let pick = firstAvailable else { return }
        splitSelectedCategory = pick
    }

    /// [2026-04-23] 스티키 상단 헤더 — 카테고리 타이틀 + 글로벌 검색 + 로딩 배너
    @ViewBuilder
    private var stickyCategoryGridHeader: some View {
        VStack(spacing: 0) {
            categoryHeader
                .padding(.bottom, DesignTokens.Spacing.md)

            globalSearchBar
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.md)

            if viewModel.isLoadingStats && !viewModel.allStatChannels.isEmpty {
                statsLoadingBanner
                    .transition(.opacity)
            }
        }
        // [Refine 2026-05-01] surfaceBase 단색 + Divider(0.4) 조합을
        // 통일 `menuTopChrome` 으로 대체 — 본문과 자연스럽게 흡수되는 페이드 + 페이드 디바이더.
        .menuTopChrome()
        .ignoresSafeArea(edges: .horizontal)
        .zIndex(10)
    }

    // [M3] 글로벌 검색 바
    private var globalSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(
                    globalSearchText.isEmpty
                        ? DesignTokens.Colors.textTertiary
                        : DesignTokens.Colors.chzzkGreen)
            TextField("전체 카테고리에서 채널·방송 검색... ( / 키)", text: $globalSearchText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($isGlobalSearchFocused)
            if !globalSearchText.isEmpty {
                Text("\(globalSearchResults.count)건")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .contentTransition(.numericText())
                Button {
                    withAnimation(DesignTokens.Animation.fast) { globalSearchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.85))
                .accessibilityLabel("전체 검색 지우기")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            DesignTokens.Colors.surfaceElevated,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isGlobalSearchFocused
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : (globalSearchText.isEmpty
                            ? DesignTokens.Glass.borderColor
                            : DesignTokens.Colors.chzzkGreen.opacity(0.4)),
                    lineWidth: 0.75
                )
        }
        .animation(DesignTokens.Animation.fast, value: isGlobalSearchFocused)
        .animation(DesignTokens.Animation.fast, value: globalSearchText.isEmpty)
    }

    // [M3] 글로벌 검색 결과 그리드
    @ViewBuilder
    private var globalSearchResultsView: some View {
        if globalSearchResults.isEmpty {
            emptyState("'\(globalSearchText)' 검색 결과가 없습니다")
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("전체 검색 결과")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("· \(globalSearchResults.count)개")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                LazyVGrid(columns: channelGridColumns, spacing: 12) {
                    ForEach(globalSearchResults) { channel in
                        CategoryChannelCard(channel: channel, showCategoryBadge: true) {
                            router.navigateToWatch(channelId: channel.channelId)
                        }
                        .equatable()
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
    }

    // [M5] 고정/전체 섹션 헤더
    private var pinnedSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.accentOrange)
            Text("고정")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("\(pinnedGroups.count)")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var allSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("전체")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    /// [Lightweight 2026-04-28] 고정 아래·전체 위에 드러나는 "인기" 섹션 헤더.
    private var popularSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.live)
            Text("인기")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("\(popularGroups.count)")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    // [M5/M10] 그리드 — pin 토글 컨텍스트 메뉴 + Cmd+1–9 키보드 바인딩
    // [2026-04-23] .equatable() 로 불필요한 재평가 차단 + 키바인딩 충돌 제거
    private func categoryGrid(groups: [(category: String, channels: [LiveChannelItem])])
        -> some View
    {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.element.category) { index, group in
                CategoryGridCard(
                    category: group.category,
                    liveCount: group.channels.count,
                    viewerTotal: group.channels.reduce(0) { $0 + $1.viewerCount },
                    isPinned: pinnedCategories.contains(group.category),
                    accentColor: accentColor(for: group.category)
                ) {
                    withAnimation(DesignTokens.Animation.contentTransition) {
                        selectedCategory = group.category
                    }
                }
                .equatable()
                .contextMenu {
                    Button {
                        togglePin(group.category)
                    } label: {
                        if pinnedCategories.contains(group.category) {
                            Label("고정 해제", systemImage: "pin.slash")
                        } else {
                            Label("카테고리 고정", systemImage: "pin")
                        }
                    }
                }
                // [M10/2026-04-23] Cmd+1..9 — 상위 9개에만 부여 (10개 이상 시 "0" 공유 충돌 제거)
                .modifier(ConditionalKeyboardShortcut(index: index))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.xl)
    }

    private var categoryHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("CATEGORY")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .tracking(1.8)
                }
                Text("카테고리")
                    .font(DesignTokens.Typography.custom(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                HStack(spacing: 6) {
                    Text("\(categorizedChannels.count)개 카테고리")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .contentTransition(.numericText())
                    Text("·")
                        .foregroundStyle(DesignTokens.Colors.border)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 5, height: 5)
                        Text("\(sourceChannels.count)개 라이브 중")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.live.opacity(0.9))
                            .contentTransition(.numericText())
                    }
                    if viewModel.isLoadingStats {
                        HStack(spacing: 4) {
                            Text("·")
                                .foregroundStyle(DesignTokens.Colors.border)
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(DesignTokens.Colors.chzzkGreen)
                            Text("전체 수집 중")
                                .font(DesignTokens.Typography.captionMedium)
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.8))
                        }
                        .transition(.opacity)
                    }
                }
            }
            Spacer()
            if prefExperimentalTrendMode {
                viewModePicker
            }
            categorySortMenu
            refreshButton
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        // [Lightweight 2026-04-28] sticky header 높이 수축: xl(28) → lg(20).
        .padding(.top, DesignTokens.Spacing.lg)
    }
    // [M4] 카테고리 정렬 메뉴
    private var categorySortMenu: some View {
        Menu {
            ForEach(CategorySortMode.allCases) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        categorySortRaw = mode.rawValue
                    }
                } label: {
                    if categorySort == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 34, height: 34)
                .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                .overlay {
                    Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("정렬: \(categorySort.label)")
        .accessibilityLabel("카테고리 정렬, 현재 \(categorySort.label)")
    }

    /// [Trend Atlas 2026-04-28] 보기 모드 picker (실험 플래그 ON일 때만 노출).
    private var viewModePicker: some View {
        Menu {
            ForEach(CategoryViewMode.allCases) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.contentTransition) {
                        viewModeRaw = mode.rawValue
                    }
                } label: {
                    if viewMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            }
        } label: {
            Image(systemName: viewMode.icon)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 34, height: 34)
                .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                .overlay {
                    Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("보기: \(viewMode.label)")
        .accessibilityLabel("카테고리 보기, 현재 \(viewMode.label)")
    }

    // [H8] TimelineView 기반 continuous rotation (튕김 제거)
    // [H10] 중복 탭 가드
    private var refreshButton: some View {
        Button {
            guard !isRefreshing, !viewModel.isLoadingStats else { return }
            Task {
                isRefreshing = true
                await viewModel.loadLiveChannels()
                // [C2] allStatChannels wipe 제거 — loadAllStatsChannels 내부에서 성공 시 replace
                await viewModel.loadAllStatsChannels()
                isRefreshing = false
            }
        } label: {
            TimelineView(
                .animation(minimumInterval: isRefreshing ? 1.0 / 60.0 : 1.0, paused: !isRefreshing)
            ) { ctx in
                let angle =
                    isRefreshing
                    ? Angle.degrees(
                        ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                            * 360)
                    : .zero
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(
                        isRefreshing
                            ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary
                    )
                    .rotationEffect(angle)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .disabled(isRefreshing || viewModel.isLoadingStats)
        .help("새로고침")
        .accessibilityLabel(isRefreshing ? "새로고침 중" : "카테고리 새로고침")
    }

    // MARK: - 채널 목록

    // [2026-04-23] 상단 헤더 + 검색바를 ScrollView 밖으로 분리 → 스크롤 시 항상 고정.
    //              그 아래에서만 썸네일 그리드가 스크롤되며 헤더 하단을 통과한다.
    private func channelListView(for category: String) -> some View {
        VStack(spacing: 0) {
            stickyChannelListHeader(for: category)

            if channelsInCategory.isEmpty && !channelSearchText.isEmpty {
                ScrollView {
                    emptyState("'\(channelSearchText)' 검색 결과가 없습니다")
                }
            } else if channelsInCategory.isEmpty {
                ScrollView {
                    emptyState("\(category) 카테고리 라이브가 없습니다")
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id("channelListTop")
                        LazyVGrid(columns: channelGridColumns, spacing: 12) {
                            ForEach(pagedChannelsInCategory) { channel in
                                CategoryChannelCard(channel: channel) {
                                    router.navigateToWatch(channelId: channel.channelId)
                                }
                                .equatable()
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)

                        // 채널 목록 페이징 바
                        if channelPageCount > 1 {
                            channelPagingBar(
                                currentPage: channelListPage,
                                pageCount: channelPageCount,
                                total: channelsInCategory.count
                            ) { page in
                                withAnimation(DesignTokens.Animation.snappy) {
                                    channelListPage = page
                                }
                            }
                            .padding(.top, DesignTokens.Spacing.lg)
                            .padding(.bottom, DesignTokens.Spacing.xl)
                        } else {
                            Spacer().frame(height: DesignTokens.Spacing.xl)
                        }
                    }
                    .scrollClipDisabled(false)
                    // 페이지 전환 시 최상단 복귀
                    .onChange(of: channelListPage) { _, _ in
                        withAnimation(nil) { proxy.scrollTo("channelListTop", anchor: .top) }
                    }
                    // 검색·정렬 변경 시 1페이지 리셋
                    .onChange(of: channelSearchText) { _, _ in resetChannelPage() }
                    .onChange(of: channelSortRaw) { _, _ in resetChannelPage() }
                    .onChange(of: selectedCategory) { _, _ in resetChannelPage() }
                }
            }
        }
    }

    /// [2026-04-23] 스티키 헤더 — 상단에 고정되며 시각적 구분선/배경 제공
    @ViewBuilder
    private func stickyChannelListHeader(for category: String) -> some View {
        VStack(spacing: 0) {
            channelListHeader(for: category)
                .padding(.bottom, DesignTokens.Spacing.md)
            channelSearchBar
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.md)
        }
        // [Refine 2026-05-01] 그리드 헤더와 동일한 통일 크롬 적용.
        .menuTopChrome()
        .ignoresSafeArea(edges: .horizontal)
        .zIndex(10)
    }

    private func channelListHeader(for category: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(DesignTokens.Animation.contentTransition) {
                        selectedCategory = nil
                        // [H9] 뒤로가기 시 검색 + 타입필터 리셋으로 세션 초기화
                        channelSearchText = ""
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(DesignTokens.Typography.micro)
                        Text("카테고리")
                            .font(DesignTokens.Typography.captionSemibold)
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                    }
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.94))
                .accessibilityLabel("카테고리 목록으로 돌아가기")
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(accentColor(for: category))
                        .frame(width: 4, height: 24)
                    Text(category)
                        .font(
                            DesignTokens.Typography.custom(
                                size: 22, weight: .bold, design: .rounded)
                        )
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                let count = sourceChannels.filter {
                    ($0.categoryName ?? Self.uncategorizedLabel) == category
                }.count
                let totalViewers = sourceChannels.filter {
                    ($0.categoryName ?? Self.uncategorizedLabel) == category
                }.reduce(0) { $0 + $1.viewerCount }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 5, height: 5)
                        Text("\(count)개 라이브 중")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.live.opacity(0.85))
                            .contentTransition(.numericText())
                    }
                    // [T07] 총 시청자 수
                    if totalViewers > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text(compactCount(totalViewers))
                                .font(DesignTokens.Typography.captionMedium)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .contentTransition(.numericText())
                        }
                    }
                }
            }
            Spacer()
            channelSortMenu
            // [M5] 헤더에서도 즐겨찾기 토글
            Button {
                togglePin(category)
            } label: {
                Image(systemName: pinnedCategories.contains(category) ? "pin.fill" : "pin")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(
                        pinnedCategories.contains(category)
                            ? DesignTokens.Colors.accentOrange
                            : DesignTokens.Colors.textSecondary
                    )
                    .symbolEffect(.bounce, value: pinnedCategories.contains(category))
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                    }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .help(pinnedCategories.contains(category) ? "고정 해제" : "카테고리 고정")
            .accessibilityLabel(pinnedCategories.contains(category) ? "고정 해제" : "카테고리 고정")
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.xl)
    }

    // [M4] 채널 정렬 메뉴
    private var channelSortMenu: some View {
        Menu {
            ForEach(ChannelSortMode.allCases) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        channelSortRaw = mode.rawValue
                    }
                } label: {
                    if channelSort == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                Text(channelSort.label)
                    .font(DesignTokens.Typography.micro)
                    .lineLimit(1)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
            .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("채널 정렬: \(channelSort.label)")
        .accessibilityLabel("채널 정렬, 현재 \(channelSort.label)")
    }

    private var channelSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(
                    channelSearchText.isEmpty
                        ? DesignTokens.Colors.textTertiary
                        : DesignTokens.Colors.chzzkGreen)
            TextField("채널, 방송 제목 검색...", text: $channelSearchText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($isChannelSearchFocused)
            if !channelSearchText.isEmpty {
                Button {
                    withAnimation(DesignTokens.Animation.fast) { channelSearchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.85))
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            DesignTokens.Colors.surfaceElevated,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    channelSearchText.isEmpty
                        ? DesignTokens.Glass.borderColor
                        : DesignTokens.Colors.chzzkGreen.opacity(0.4),
                    lineWidth: 0.75  // [H4] 고정
                )
        }
        .animation(DesignTokens.Animation.fast, value: channelSearchText.isEmpty)
    }

    // MARK: - 카테고리 타입 필터 (H2: 동적)

    private var categoryTypeFilter: some View {
        // [Lightweight 2026-04-28] type 가 8개 이상 되면 한 줄 chip swarm 대신 horizontal scroll fallback.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(availableTypeFilters, id: \.value) { item in
                    typeFilterButton(label: item.label, icon: item.icon, value: item.value)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableTypeFilters, id: \.value) { item in
                        typeFilterButton(label: item.label, icon: item.icon, value: item.value)
                    }
                }
            }
        }
    }

    private func typeFilterButton(label: String, icon: String, value: String?) -> some View {
        let isSelected = selectedTypeFilter == value
        return Button {
            withAnimation(DesignTokens.Animation.snappy) {
                selectedTypeFilter = value
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(label)
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .foregroundStyle(
                isSelected
                    ? DesignTokens.Colors.background
                    : DesignTokens.Colors.textSecondary
            )
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background {
                if isSelected {
                    Capsule().fill(DesignTokens.Colors.chzzkGreen)
                } else {
                    Capsule().fill(DesignTokens.Colors.surfaceElevated)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected
                            ? DesignTokens.Colors.chzzkGreen
                            : DesignTokens.Glass.borderColorLight,
                        lineWidth: 0.75  // [H4] 고정
                    )
            }
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))  // [M11]
        .animation(DesignTokens.Animation.snappy, value: isSelected)
        .accessibilityLabel(isSelected ? "\(label) 필터, 선택됨" : "\(label) 필터")
    }

    // MARK: - 공통 서브뷰

    private var statsLoadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(DesignTokens.Colors.chzzkGreen)
            Text("모든 카테고리 로드 중...")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)  // [M12] 고정 높이
        .background(DesignTokens.Colors.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.1)
            Text("불러오는 중...")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func emptyState(_ message: String) -> some View {
        // [M6] tv.slash → square.grid.2x2.slash (카테고리 맥락에 더 적합)
        EmptyStateView(icon: "square.grid.2x2.slash", title: message, style: .panel)
            .frame(minHeight: 260)
    }

    // [C6] 전체 통계 수집 실패 시 명시적 에러 + 재시도
    private func errorState(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignTokens.Colors.warning)
                .symbolEffect(.pulse, options: .repeat(2))
            Text("카테고리 정보를 불러오지 못했습니다")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(message)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button {
                Task {
                    await viewModel.loadLiveChannels()
                    await viewModel.loadAllStatsChannels()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("다시 시도")
                        .font(DesignTokens.Typography.captionSemibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.95))
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(DesignTokens.Spacing.xl)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - [C3] 결정적 accent color (StableHash)

    private func accentColor(for category: String) -> Color {
        let palette: [Color] = [
            DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.accentBlue,
            DesignTokens.Colors.accentPurple, DesignTokens.Colors.accentPink,
            DesignTokens.Colors.accentOrange, Color(hex: 0x00C9A7),
            Color(hex: 0xFF6B6B), Color(hex: 0x4ECDC4),
        ]
        return palette[StableHash.index(category, modulo: palette.count)]
    }

    // MARK: - Paging bar

    /// 하단 페이징 네비게이션 바.
    private var categoryPagingBar: some View {
        HStack(spacing: 8) {
            // 이전 버튼
            pagingNavButton(systemImage: "chevron.left", label: "이전") {
                guard categoryGridPage > 0 else { return }
                withAnimation(DesignTokens.Animation.snappy) { categoryGridPage -= 1 }
            }
            .disabled(categoryGridPage == 0)

            // 페이지 번호 버튼 (최대 7개 노출)
            pagingNumberButtons(currentPage: categoryGridPage, pageCount: categoryPageCount) {
                page in
                withAnimation(DesignTokens.Animation.snappy) { categoryGridPage = page }
            }

            // 다음 버튼
            pagingNavButton(systemImage: "chevron.right", label: "다음") {
                guard categoryGridPage < categoryPageCount - 1 else { return }
                withAnimation(DesignTokens.Animation.snappy) { categoryGridPage += 1 }
            }
            .disabled(categoryGridPage == categoryPageCount - 1)

            Spacer(minLength: 0)

            // 범위 표시 (예: 48 / 120개)
            let start = categoryGridPage * Self.categoriesPerPage + 1
            let end = min((categoryGridPage + 1) * Self.categoriesPerPage, remainingGroups.count)
            Text("\(start)–\(end) / \(remainingGroups.count)개")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private func channelPagingBar(
        currentPage: Int, pageCount: Int, total: Int, onPageChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            pagingNavButton(systemImage: "chevron.left", label: "이전") {
                guard currentPage > 0 else { return }
                onPageChange(currentPage - 1)
            }
            .disabled(currentPage == 0)

            pagingNumberButtons(currentPage: currentPage, pageCount: pageCount) { page in
                onPageChange(page)
            }

            pagingNavButton(systemImage: "chevron.right", label: "다음") {
                guard currentPage < pageCount - 1 else { return }
                onPageChange(currentPage + 1)
            }
            .disabled(currentPage == pageCount - 1)

            Spacer(minLength: 0)

            let start = currentPage * Self.channelsPerPage + 1
            let end = min((currentPage + 1) * Self.channelsPerPage, total)
            Text("\(start)–\(end) / \(total)개")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    /// 이전/다음 화살표 버튼
    private func pagingNavButton(systemImage: String, label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 30, height: 28)
                .background(
                    DesignTokens.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                }
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    /// 최대 7개 페이지 번호 버튼 (현재 페이지 주위 컨텍스트 표시)
    @ViewBuilder
    private func pagingNumberButtons(
        currentPage: Int, pageCount: Int, onSelect: @escaping (Int) -> Void
    ) -> some View {
        let maxShow = 7
        let pages: [Int] = {
            guard pageCount > maxShow else { return Array(0..<pageCount) }
            let half = maxShow / 2
            let start = max(0, min(currentPage - half, pageCount - maxShow))
            return Array(start..<(start + maxShow))
        }()

        HStack(spacing: 4) {
            ForEach(pages, id: \.self) { page in
                let isActive = page == currentPage
                Button {
                    onSelect(page)
                } label: {
                    Text("\(page + 1)")
                        .font(
                            isActive
                                ? DesignTokens.Typography.custom(size: 12, weight: .bold)
                                : DesignTokens.Typography.micro
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            isActive
                                ? DesignTokens.Colors.background
                                : DesignTokens.Colors.textSecondary
                        )
                        .frame(width: 28, height: 28)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(DesignTokens.Colors.chzzkGreen)
                            } else {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(DesignTokens.Colors.surfaceElevated)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(
                                    isActive
                                        ? DesignTokens.Colors.chzzkGreen
                                        : DesignTokens.Glass.borderColorLight,
                                    lineWidth: isActive ? 0 : 0.5
                                )
                        }
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.9))
                .animation(DesignTokens.Animation.snappy, value: isActive)
                .accessibilityLabel("\(page + 1)페이지\(isActive ? ", 현재" : "")")
            }
        }
    }
}

// MARK: - [C3] Back-compat type alias (deprecated)
// StableHash 로 이관됨. 기존 외부 참조 호환을 위해 유지.
@available(*, deprecated, message: "Use StableHash from CViewCore instead")
enum CategoryHash {
    public static func fnv1a(_ s: String) -> UInt64 { StableHash.fnv1a(s) }
}

// MARK: - [M10/2026-04-23] 조건부 키보드 단축키 (상위 9개에만 Cmd+N 부여)

private struct ConditionalKeyboardShortcut: ViewModifier {
    let index: Int
    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(
                KeyEquivalent(Character("\(index + 1)")),
                modifiers: .command
            )
        } else {
            content
        }
    }
}

// MARK: - Category Grid Card

// [2026-04-23] Equatable 채택 → `.equatable()` 사용 시 부모 상태 변경에도 입력값 동일 시 body 재평가 스킵
private struct CategoryGridCard: View, Equatable {
    let category: String
    let liveCount: Int
    let viewerTotal: Int  // [T06] 총 시청자 수
    let isPinned: Bool  // [M5]
    let accentColor: Color
    let onTap: () -> Void

    nonisolated static func == (lhs: CategoryGridCard, rhs: CategoryGridCard) -> Bool {
        lhs.category == rhs.category
            && lhs.liveCount == rhs.liveCount
            && lhs.viewerTotal == rhs.viewerTotal
            && lhs.isPinned == rhs.isPinned
    }

    @State private var isHovered = false

    // [C3] 결정적 icon — StableHash 기반
    private var categoryIcon: String {
        let icons = [
            "gamecontroller.fill", "trophy.fill", "star.fill", "flame.fill",
            "bolt.fill", "music.note", "sportscourt.fill", "theatermasks.fill",
            "paintbrush.fill", "waveform", "mic.fill", "tv.fill",
            "cube.fill", "map.fill", "person.3.fill", "sparkles",
        ]
        return icons[StableHash.index(category, modulo: icons.count)]
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // [Lightweight 2026-04-28] 배경 단순화: 3-stop gradient + 하단 페이드 overlay
                // (총 2개 LinearGradient layer) → 1개 2-stop gradient. CAGradientLayer 1개 절약.
                LinearGradient(
                    colors: [accentColor.opacity(0.20), DesignTokens.Colors.surfaceBase],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 중앙 아이콘 (38 → 30, opacity 0.52 → 0.38 — 더 조용한 느낌)
                Image(systemName: categoryIcon)
                    .font(DesignTokens.Typography.custom(size: 30, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.38))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -8)

                // 하단 텍스트 정보
                VStack(alignment: .leading, spacing: 2) {
                    Text(category)
                        .font(DesignTokens.Typography.custom(size: 12.5, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DesignTokens.Colors.live)
                                .frame(width: 4, height: 4)
                            Text("라이브 \(liveCount)개")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .contentTransition(.numericText())
                        }
                        // [T06] 총 시청자 수
                        if viewerTotal > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(
                                        DesignTokens.Typography.custom(size: 8, weight: .semibold)
                                    )
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                Text(compactCount(viewerTotal))
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.sm)

                // 좌상단 핀 배지만 유지 — 우상단 라이브 수 배지는 하단 텍스트와 중복이라 제거
                if isPinned {
                    VStack {
                        HStack {
                            Image(systemName: "pin.fill")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                                .padding(4)
                                .background(
                                    DesignTokens.Colors.surfaceBase.opacity(0.85), in: Circle()
                                )
                                .transition(.scale.combined(with: .opacity))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(DesignTokens.Spacing.xs)
                }
            }
            // [Lightweight 2026-04-28] 카드 높이 140 → 118 (정보 밀도 유지하면서 수직 밀도 감소).
            .frame(height: 118)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(
                        isHovered
                            ? accentColor.opacity(0.65)
                            : DesignTokens.Colors.border.opacity(0.5),
                        lineWidth: 1
                    )
            }
            // [Perf] compositingGroup 제거 → backing layer 항상 생성 낭비 방지
            .shadow(
                color: .black.opacity(isHovered ? 0.18 : 0.0), radius: isHovered ? 5 : 0, x: 0,
                y: isHovered ? 2 : 0)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))  // [M11]
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .animation(DesignTokens.Animation.snappy, value: isPinned)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .accessibilityLabel(
            "\(isPinned ? "고정됨, " : "")\(category) 카테고리, 라이브 \(liveCount)개, 시청자 \(compactCount(viewerTotal))"
        )
    }
}

// MARK: - Category Rail Row (Split Explorer)

/// [Split Explorer 2026-04-28] 좌측 rail의 dense row.
/// 카드가 아닌 row 형태로, 선택 시 accent bar + tinted background 만 변경.
private struct CategoryRailRow: View, Equatable {
    let category: String
    let liveCount: Int
    let viewerTotal: Int  // [T08] 총 시청자 수
    let isSelected: Bool
    let isPinned: Bool
    let accentColor: Color
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    nonisolated static func == (lhs: CategoryRailRow, rhs: CategoryRailRow) -> Bool {
        lhs.category == rhs.category
            && lhs.liveCount == rhs.liveCount
            && lhs.viewerTotal == rhs.viewerTotal
            && lhs.isSelected == rhs.isSelected
            && lhs.isPinned == rhs.isPinned
            && lhs.accentColor == rhs.accentColor
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // 좌측 accent bar (선택 시만 표시)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor)
                    .frame(width: 3)
                    .opacity(isSelected ? 1 : 0)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }

                Text(category)
                    .font(
                        isSelected
                            ? DesignTokens.Typography.captionSemibold
                            : DesignTokens.Typography.caption
                    )
                    .foregroundStyle(
                        isSelected
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.textSecondary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(liveCount)")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                    // [T08] 시청자 수 compact
                    if viewerTotal > 0 {
                        Text(compactCount(viewerTotal))
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, DesignTokens.Spacing.md)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(accentColor.opacity(0.14))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated.opacity(0.6))
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.snappy, value: isSelected)
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .accessibilityLabel(
            "\(isPinned ? "고정됨, " : "")\(category) 카테고리, 라이브 \(liveCount)개, 시청자 \(compactCount(viewerTotal))\(isSelected ? ", 선택됨" : "")"
        )
    }
}

// MARK: - Trend Atlas Components (실험 플래그)

/// [Trend Atlas 2026-04-28] 큰 숫자 압축 포맷 (1.2K, 12.3K, 1.2M).
private func compactCount(_ n: Int) -> String {
    let abs = Swift.abs(n)
    if abs >= 1_000_000 {
        return String(format: "%.1fM", Double(n) / 1_000_000)
    } else if abs >= 1_000 {
        return String(format: "%.1fK", Double(n) / 1_000)
    }
    return "\(n)"
}

/// 상단 spotlight 카드 — primary(rank 1)는 크게, 보조(rank 2~3)는 작게.
private struct TrendSpotlightCard: View, Equatable {
    let rank: Int
    let category: String
    let liveCount: Int
    let viewerTotal: Int
    let accentColor: Color
    let isPrimary: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    nonisolated static func == (lhs: TrendSpotlightCard, rhs: TrendSpotlightCard) -> Bool {
        lhs.rank == rhs.rank
            && lhs.category == rhs.category
            && lhs.liveCount == rhs.liveCount
            && lhs.viewerTotal == rhs.viewerTotal
            && lhs.accentColor == rhs.accentColor
            && lhs.isPrimary == rhs.isPrimary
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: isPrimary ? 10 : 6) {
                HStack(spacing: 6) {
                    Text("#\(rank)")
                        .font(
                            DesignTokens.Typography.custom(
                                size: isPrimary ? 12 : 10, weight: .bold, design: .rounded)
                        )
                        .foregroundStyle(accentColor)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        .foregroundStyle(
                            DesignTokens.Colors.textTertiary.opacity(isHovered ? 1.0 : 0.5))
                }
                Text(category)
                    .font(
                        isPrimary
                            ? DesignTokens.Typography.custom(
                                size: 22, weight: .bold, design: .rounded)
                            : DesignTokens.Typography.custom(
                                size: 15, weight: .semibold, design: .rounded)
                    )
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 5, height: 5)
                        Text("\(liveCount) 라이브")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    Text("·")
                        .foregroundStyle(DesignTokens.Colors.border)
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text(compactCount(viewerTotal))
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, isPrimary ? DesignTokens.Spacing.lg : DesignTokens.Spacing.md)
            .padding(.vertical, isPrimary ? DesignTokens.Spacing.lg : DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: isPrimary ? 148 : 70, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(isPrimary ? 0.22 : 0.16),
                                DesignTokens.Colors.surfaceBase,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(accentColor.opacity(isHovered ? 0.45 : 0.18), lineWidth: 0.8)
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(isHovered ? 0.18 : 0.0), radius: isHovered ? 6 : 0, x: 0,
                y: isHovered ? 3 : 0
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .accessibilityLabel(
            "순위 \(rank)위 \(category), 라이브 \(liveCount)개, 총 시청자 \(compactCount(viewerTotal))")
    }
}

/// 트렌드 랭킹 dense row.
private struct TrendRankingRow: View, Equatable {
    let rank: Int
    let category: String
    let liveCount: Int
    let viewerTotal: Int
    let accentColor: Color
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    nonisolated static func == (lhs: TrendRankingRow, rhs: TrendRankingRow) -> Bool {
        lhs.rank == rhs.rank
            && lhs.category == rhs.category
            && lhs.liveCount == rhs.liveCount
            && lhs.viewerTotal == rhs.viewerTotal
            && lhs.accentColor == rhs.accentColor
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text("#\(rank)")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? accentColor : DesignTokens.Colors.textTertiary)
                    .frame(width: 32, alignment: .leading)
                    .monospacedDigit()
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor)
                    .frame(width: 3, height: 18)
                Text(category)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 4, height: 4)
                    Text("\(liveCount)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                }
                .frame(width: 56, alignment: .trailing)
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(DesignTokens.Typography.custom(size: 8, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(compactCount(viewerTotal))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                }
                .frame(width: 64, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                    .foregroundStyle(
                        DesignTokens.Colors.textTertiary.opacity(isHovered ? 1.0 : 0.5))
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isHovered {
                    Rectangle().fill(accentColor.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .accessibilityLabel(
            "순위 \(rank)위 \(category), 라이브 \(liveCount)개, 총 시청자 \(compactCount(viewerTotal))")
    }
}

// [2026-04-23] Equatable — LiveChannelItem 는 이미 Equatable. 셀 재평가 스킵.
private struct CategoryChannelCard: View, Equatable {
    let channel: LiveChannelItem
    let showCategoryBadge: Bool
    let onTap: () -> Void

    init(channel: LiveChannelItem, showCategoryBadge: Bool = false, onTap: @escaping () -> Void) {
        self.channel = channel
        self.showCategoryBadge = showCategoryBadge
        self.onTap = onTap
    }

    nonisolated static func == (lhs: CategoryChannelCard, rhs: CategoryChannelCard) -> Bool {
        lhs.channel == rhs.channel && lhs.showCategoryBadge == rhs.showCategoryBadge
    }

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            // Color.clear 가 레이아웃 앵커 — 16:9 비율 고정.
            // LiveThumbnailView 는 .background 로 처리하여 레이아웃 크기에 영향 없음.
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background {
                    LiveThumbnailView(
                        channelId: channel.channelId,
                        thumbnailUrl: URL(string: channel.thumbnailUrl ?? ""),
                        isLive: false
                    )
                    .scaledToFill()
                    .clipped()
                }
                // 하단 그라디언트 + 채널 정보
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.black.opacity(0.90), .black.opacity(0.28), .clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                                    Circle().fill(DesignTokens.Colors.surfaceBase)
                                }
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                                .overlay {
                                    Circle().strokeBorder(
                                        DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                                }

                                Text(channel.channelName)
                                    .font(DesignTokens.Typography.captionSemibold)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    .lineLimit(1)
                            }
                            Text(channel.liveTitle)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textOnDarkMediaMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            // [T05] 글로벌 검색 시 카테고리 배지
                            if showCategoryBadge, let cat = channel.categoryName {
                                Text(cat)
                                    .font(
                                        DesignTokens.Typography.custom(size: 9, weight: .semibold)
                                    )
                                    .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                    .padding(.horizontal, DesignTokens.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(
                                        DesignTokens.Colors.surfaceElevated.opacity(0.85),
                                        in: Capsule()
                                    )
                                    .overlay {
                                        Capsule().strokeBorder(
                                            DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                                    }
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.bottom, DesignTokens.Spacing.md)
                    }
                }
                // LIVE 뱃지 + 시청자 수 (좌상단)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 8, weight: .black))
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(
                                DesignTokens.Colors.live,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(DesignTokens.Typography.custom(size: 8))
                            Text(channel.formattedViewerCount)
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        }
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                        }
                    }
                    .padding(DesignTokens.Spacing.xs)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                // [T04] 경량 hover: shadow 없이 border 색상만 전환
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(
                            isHovered
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.55)
                                : DesignTokens.Colors.border.opacity(0.5),
                            lineWidth: isHovered ? 1.2 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.channelName, forType: .string)
            } label: {
                Label("채널 이름 복사", systemImage: "person.crop.circle")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.liveTitle, forType: .string)
            } label: {
                Label("방송 제목 복사", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                if let url = URL(string: "https://chzzk.naver.com/live/\(channel.channelId)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("치지직에서 열기", systemImage: "safari")
            }
        }
        .accessibilityLabel(
            "\(channel.channelName) 방송 보기, \(channel.liveTitle), 시청자 \(channel.formattedViewerCount)"
        )
    }
}
