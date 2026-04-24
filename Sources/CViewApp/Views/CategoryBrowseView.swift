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

import SwiftUI
import CViewCore
import CViewUI

// MARK: - ContentState (C1/H1 flatten)

private enum CategoryContentState: Equatable {
    case initialLoading          // 최초 liveChannels 페이지 로드 중
    case partial                 // liveChannels 보임, 전체 통계 수집 중
    case ready                   // 전체 통계 반영 완료
    case empty                   // 라이브 없음
    case error(String)           // 수집 실패
}

// MARK: - Sort Options (M4)

enum CategorySortMode: String, CaseIterable, Identifiable {
    case liveCountDesc      // 라이브 수 많은 순 (기본)
    case nameAsc            // 가나다
    var id: String { rawValue }
    var label: String {
        switch self {
        case .liveCountDesc: return "라이브 수"
        case .nameAsc:       return "이름순"
        }
    }
    var icon: String {
        switch self {
        case .liveCountDesc: return "chart.bar.fill"
        case .nameAsc:       return "textformat.abc"
        }
    }
}

enum ChannelSortMode: String, CaseIterable, Identifiable {
    case viewersDesc        // 시청자 많은 순 (기본)
    case viewersAsc
    case nameAsc            // 채널명 가나다
    case titleAsc           // 방송 제목 가나다
    var id: String { rawValue }
    var label: String {
        switch self {
        case .viewersDesc: return "시청자 많은 순"
        case .viewersAsc:  return "시청자 적은 순"
        case .nameAsc:     return "채널명"
        case .titleAsc:    return "방송 제목"
        }
    }
    var icon: String {
        switch self {
        case .viewersDesc: return "person.3.sequence.fill"
        case .viewersAsc:  return "person.2"
        case .nameAsc:     return "textformat.abc"
        case .titleAsc:    return "text.alignleft"
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
    @State private var selectedTypeFilter: String? = nil   // nil=전체

    // [M3] 글로벌 검색 (카테고리 단계에서도 채널명/제목 교차 검색)
    @State private var globalSearchText: String = ""
    @FocusState private var isGlobalSearchFocused: Bool
    @FocusState private var isChannelSearchFocused: Bool

    // [M4] 정렬
    @AppStorage("category.sortMode")
    private var categorySortRaw: String = CategorySortMode.liveCountDesc.rawValue
    @AppStorage("category.channelSortMode")
    private var channelSortRaw: String = ChannelSortMode.viewersDesc.rawValue
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
           let s = String(data: data, encoding: .utf8) {
            pinnedCategoriesRaw = s
        }
    }

    // [H5] 너비 quantize 상수 (100px 단위) — 칼럼 배열 재계산 억제
    private static let widthQuantizeStep: CGFloat = 100

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
        let cardWidth: CGFloat = 160
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
        let filtered = selectedTypeFilter == nil
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

    /// [M3] 글로벌 검색 결과 (카테고리 단계에서 전체 채널 교차 검색)
    private var globalSearchResults: [LiveChannelItem] {
        let q = globalSearchText.lowercased()
        guard !q.isEmpty else { return [] }
        return sourceChannels
            .filter {
                $0.channelName.lowercased().contains(q) ||
                $0.liveTitle.lowercased().contains(q) ||
                ($0.categoryName?.lowercased().contains(q) ?? false)
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
                $0.channelName.lowercased().contains(q) ||
                $0.liveTitle.lowercased().contains(q)
            }
        }
        // [M4] 채널 정렬 — 동률 시 channelId ASC 로 결정성 확보
        return sortChannels(searched, by: channelSort)
    }

    private func sortChannels(_ list: [LiveChannelItem], by mode: ChannelSortMode) -> [LiveChannelItem] {
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
           viewModel.allStatChannels.isEmpty, viewModel.liveChannels.isEmpty {
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
        ZStack {
            if let category = selectedCategory {
                channelListView(for: category)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                categoryGridView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(DesignTokens.Animation.contentTransition, value: selectedCategory)
        .contentBackground()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // [H5] 100px 단위 quantize — 리사이즈 중 레이아웃 재계산 폭발 억제
            let quantized = (width / Self.widthQuantizeStep).rounded() * Self.widthQuantizeStep
            if abs(contentWidth - quantized) >= Self.widthQuantizeStep {
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
                    ScrollView {
                        VStack(spacing: 0) {
                            categoryTypeFilter
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.top, DesignTokens.Spacing.sm)
                                .padding(.bottom, DesignTokens.Spacing.sm)

                            if !pinnedGroups.isEmpty {
                                pinnedSectionHeader
                                categoryGrid(groups: pinnedGroups)
                                    .padding(.bottom, DesignTokens.Spacing.lg)
                                allSectionHeader
                            }
                            categoryGrid(groups: unpinnedGroups)
                        }
                        .animation(DesignTokens.Animation.smooth, value: pinnedCategoriesRaw)
                    }
                }
            }
        }
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

            Divider()
                .opacity(0.4)
        }
        .background {
            DesignTokens.Colors.surfaceBase
                .ignoresSafeArea(edges: .horizontal)
        }
        .zIndex(10)
    }

    // [M3] 글로벌 검색 바
    private var globalSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(globalSearchText.isEmpty
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
        .background(DesignTokens.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
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
                        CategoryChannelCard(channel: channel) {
                            router.navigate(to: .live(channelId: channel.channelId))
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

    // [M5/M10] 그리드 — pin 토글 컨텍스트 메뉴 + Cmd+1–9 키보드 바인딩
    // [2026-04-23] .equatable() 로 불필요한 재평가 차단 + 키바인딩 충돌 제거
    private func categoryGrid(groups: [(category: String, channels: [LiveChannelItem])]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.element.category) { index, group in
                CategoryGridCard(
                    category: group.category,
                    liveCount: group.channels.count,
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
            categorySortMenu
            refreshButton
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.xl)
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
                .overlay { Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("정렬: \(categorySort.label)")
        .accessibilityLabel("카테고리 정렬, 현재 \(categorySort.label)")
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
            TimelineView(.animation(minimumInterval: isRefreshing ? 1.0 / 60.0 : 1.0, paused: !isRefreshing)) { ctx in
                let angle = isRefreshing
                    ? Angle.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360)
                    : .zero
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(isRefreshing ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    .rotationEffect(angle)
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                    .overlay { Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }
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
                ScrollView {
                    LazyVGrid(columns: channelGridColumns, spacing: 12) {
                        ForEach(channelsInCategory) { channel in
                            CategoryChannelCard(channel: channel) {
                                router.navigate(to: .live(channelId: channel.channelId))
                            }
                            .equatable()
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                }
                .scrollClipDisabled(false)
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
            Divider()
                .opacity(0.4)
        }
        .background {
            // 불투명 배경 — 밑으로 썸네일이 지나갈 때 가독성 보장
            DesignTokens.Colors.surfaceBase
                .ignoresSafeArea(edges: .horizontal)
        }
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
                    .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.94))
                .accessibilityLabel("카테고리 목록으로 돌아가기")
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(accentColor(for: category))
                        .frame(width: 4, height: 24)
                    Text(category)
                        .font(DesignTokens.Typography.custom(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                let count = sourceChannels.filter {
                    ($0.categoryName ?? Self.uncategorizedLabel) == category
                }.count
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignTokens.Colors.live)
                        .frame(width: 5, height: 5)
                    Text("\(count)개 라이브 중")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.live.opacity(0.85))
                        .contentTransition(.numericText())
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
                    .foregroundStyle(pinnedCategories.contains(category)
                        ? DesignTokens.Colors.accentOrange
                        : DesignTokens.Colors.textSecondary)
                    .symbolEffect(.bounce, value: pinnedCategories.contains(category))
                    .frame(width: 34, height: 34)
                    .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                    .overlay { Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }
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
                .foregroundStyle(channelSearchText.isEmpty
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
        .background(DesignTokens.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
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
        HStack(spacing: 8) {
            ForEach(availableTypeFilters, id: \.value) { item in
                typeFilterButton(label: item.label, icon: item.icon, value: item.value)
            }
            Spacer()
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
            .foregroundStyle(isSelected
                ? DesignTokens.Colors.background
                : DesignTokens.Colors.textSecondary)
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
    let isPinned: Bool            // [M5]
    let accentColor: Color
    let onTap: () -> Void

    nonisolated static func == (lhs: CategoryGridCard, rhs: CategoryGridCard) -> Bool {
        lhs.category == rhs.category
            && lhs.liveCount == rhs.liveCount
            && lhs.isPinned == rhs.isPinned
    }

    @State private var isHovered = false

    // [C3] 결정적 icon — StableHash 기반
    private var categoryIcon: String {
        let icons = [
            "gamecontroller.fill", "trophy.fill", "star.fill", "flame.fill",
            "bolt.fill", "music.note", "sportscourt.fill", "theatermasks.fill",
            "paintbrush.fill", "waveform", "mic.fill", "tv.fill",
            "cube.fill", "map.fill", "person.3.fill", "sparkles"
        ]
        return icons[StableHash.index(category, modulo: icons.count)]
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // 배경 그라디언트
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.28),
                        accentColor.opacity(0.10),
                        DesignTokens.Colors.surfaceBase
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 중앙 아이콘
                Image(systemName: categoryIcon)
                    .font(DesignTokens.Typography.custom(size: 38, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.52))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -10)

                // 하단 페이드 오버레이
                LinearGradient(
                    colors: [.black.opacity(0.70), .black.opacity(0.12), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                // 하단 텍스트 정보
                VStack(alignment: .leading, spacing: 3) {
                    Text(category)
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignTokens.Colors.live)
                            .frame(width: 5, height: 5)
                        Text("라이브 \(liveCount)개")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textOnDarkMediaMuted)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.md)

                // 우상단 라이브 수 뱃지
                VStack {
                    HStack {
                        // [M5] 좌상단 핀 뱃지
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                                .padding(5)
                                .background(DesignTokens.Colors.surfaceBase.opacity(0.85), in: Circle())
                                .overlay { Circle().strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.4), lineWidth: 0.5) }
                                .transition(.scale.combined(with: .opacity))
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            Circle()
                                .fill(DesignTokens.Colors.live)
                                .frame(width: 5, height: 5)
                            Text("\(liveCount)")
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                        .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
                    }
                    Spacer()
                }
                .padding(DesignTokens.Spacing.xs)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                // [H4] lineWidth 고정 — CAShapeLayer re-tessellation 방지, color opacity만 변화
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(
                        isHovered
                            ? accentColor.opacity(0.65)
                            : DesignTokens.Colors.border.opacity(0.5),
                        lineWidth: 1
                    )
            }
            // [M7] 카드 전체를 하나의 합성 그룹으로 묶어 Metal draw 수 감축
            .compositingGroup()
            // 정적 shadow (opacity만 변화)
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.14), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))  // [M11]
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .animation(DesignTokens.Animation.snappy, value: isPinned)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .accessibilityLabel("\(isPinned ? "고정됨, " : "")\(category) 카테고리, 라이브 \(liveCount)개")
    }
}

// MARK: - Category Channel Card (H7: Button 래핑 + 접근성)

// [2026-04-23] Equatable — LiveChannelItem 는 이미 Equatable. 셀 재평가 스킵.
private struct CategoryChannelCard: View, Equatable {
    let channel: LiveChannelItem
    let onTap: () -> Void

    nonisolated static func == (lhs: CategoryChannelCard, rhs: CategoryChannelCard) -> Bool {
        lhs.channel == rhs.channel
    }

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // 썸네일 — 카테고리 목록에서는 정적 (isLive:false)
                LiveThumbnailView(
                    channelId: channel.channelId,
                    thumbnailUrl: URL(string: channel.thumbnailUrl ?? ""),
                    isLive: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(contentMode: .fill)
                .clipped()

                // 하단 그라디언트
                LinearGradient(
                    colors: [.black.opacity(0.90), .black.opacity(0.28), .clear],
                    startPoint: .bottom,
                    endPoint: UnitPoint(x: 0.5, y: 0.35)
                )

                // 하단 채널 정보
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) {
                            Circle().fill(DesignTokens.Colors.surfaceBase)
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }

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
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.md)

                // LIVE + 시청자 수 (좌상단)
                VStack {
                    HStack(spacing: 5) {
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 8, weight: .black))
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.live,
                                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(DesignTokens.Typography.custom(size: 8))
                            Text(channel.formattedViewerCount)
                                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                        .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(DesignTokens.Spacing.xs)
            }
            // [2026-04-23] \uc140 \uc804\uccb4\uc5d0 16:9 \uace0\uc815 \u2014 \uc378\ub124\uc77c\uc774 fill \ubaa8\ub4dc\uc5ec\ub3c4 \uc140 \ud06c\uae30\uac00 \uacb0\uc815\uc801\uc73c\ub85c \uacc4\uc0b0\ub428\n            .aspectRatio(16.0/9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                // [H4] lineWidth 고정
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(
                        isHovered
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.55)
                            : DesignTokens.Colors.border.opacity(0.5),
                        lineWidth: 1
                    )
            }
            .compositingGroup()
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.14), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))  // [H7/M11]
        .animation(DesignTokens.Animation.cardHover, value: isHovered)
        .onHover { isHovered = $0 }
        .customCursor(.pointingHand)
        .accessibilityLabel("\(channel.channelName) 방송 보기, \(channel.liveTitle), 시청자 \(channel.formattedViewerCount)")
    }
}
