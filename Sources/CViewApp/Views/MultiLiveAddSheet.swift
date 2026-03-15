// MARK: - MultiLiveAddSheet.swift
// CViewApp — 멀티라이브 채널 추가 시트
// 팔로잉 채널 + 라이브 검색 + 채널 ID 직접 입력

import SwiftUI
import CViewCore
import CViewNetworking

struct MultiLiveAddSheet: View {

    @Bindable var manager: MultiLiveManager
    @Environment(AppState.self) private var appState
    var isPresented: Binding<Bool>?

    // 검색 상태
    @State private var searchQuery = ""
    @State private var searchResults: [LiveInfo] = []
    @State private var channelSearchResults: [ChannelInfo] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var recentSearches: [String] = []

    // 팔로잉 상태
    @State private var followingChannels: [LiveChannelItem] = []
    @State private var isLoadingFollowing = false
    @State private var followingFilter: FollowingFilter = .all
    @State private var followingSearchText = ""

    // 공통 상태
    @State private var channelIdInput = ""
    @State private var addError: String?
    @State private var addingChannelId: String?
    @State private var recentlyAddedIds: Set<String> = []
    @State private var selectedTab: AddSheetTab = .following

    private enum AddSheetTab: String, CaseIterable {
        case following = "팔로잉"
        case search = "검색"
        case direct = "채널 ID"
    }

    private enum FollowingFilter: String, CaseIterable {
        case all = "전체"
        case liveOnly = "라이브"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            Group {
                switch selectedTab {
                case .following:
                    followingContent
                case .search:
                    searchContent
                case .direct:
                    directInputContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let error = addError {
                errorBanner(error)
            }
        }
        .onChange(of: searchQuery) { debounceSearch() }
        .task { await loadFollowingChannels() }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "rectangle.split.2x2.fill")
                .font(.title3)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)

            VStack(alignment: .leading, spacing: 1) {
                Text("채널 추가")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("최대 \(manager.effectiveMaxSessions)개 채널 동시 시청")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            sessionCounter

            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    isPresented?.wrappedValue = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var sessionCounter: some View {
        HStack(spacing: 4) {
            ForEach(0..<manager.effectiveMaxSessions, id: \.self) { i in
                Circle()
                    .fill(i < manager.sessions.count ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.6)))
    }

    // MARK: - 탭 피커

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(AddSheetTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                        if tab == .following, !followingChannels.isEmpty {
                            Text("\(followingChannels.count)")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.6)))
                        }
                    }
                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .bottom) {
            GeometryReader { geo in
                let tabWidth = geo.size.width / CGFloat(AddSheetTab.allCases.count)
                let index = AddSheetTab.allCases.firstIndex(of: selectedTab) ?? 0
                Rectangle()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: tabWidth * 0.5, height: 2)
                    .clipShape(Capsule())
                    .offset(x: tabWidth * CGFloat(index) + tabWidth * 0.25)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.borderColor)
                .frame(height: 0.5)
        }
    }

    // MARK: - 팔로잉 탭

    private var followingContent: some View {
        VStack(spacing: 0) {
            // 필터 바
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 검색 필드
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    TextField("채널명 검색", text: $followingSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                )

                // 라이브/전체 필터
                Picker("", selection: $followingFilter) {
                    ForEach(FollowingFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                // 새로고침
                Button {
                    Task { await loadFollowingChannels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .rotationEffect(.degrees(isLoadingFollowing ? 360 : 0))
                        .animation(isLoadingFollowing ? DesignTokens.Animation.loadingSpin : .default, value: isLoadingFollowing)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingFollowing)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)

            // 콘텐츠
            if isLoadingFollowing && followingChannels.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(DesignTokens.Colors.chzzkGreen)
                Spacer()
            } else if followingChannels.isEmpty {
                Spacer()
                followingEmptyView
                Spacer()
            } else if filteredFollowingChannels.isEmpty {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignTokens.Typography.custom(size: 24, weight: .light))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("일치하는 채널이 없습니다")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
            } else {
                followingList
            }
        }
    }

    private var filteredFollowingChannels: [LiveChannelItem] {
        var channels = followingChannels
        if followingFilter == .liveOnly {
            channels = channels.filter { $0.isLive }
        }
        if !followingSearchText.isEmpty {
            let query = followingSearchText.lowercased()
            channels = channels.filter { $0.channelName.lowercased().contains(query) }
        }
        // 라이브 채널 상단 정렬 (라이브 우선, 시청자 수 내림차순)
        return channels.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            return a.viewerCount > b.viewerCount
        }
    }

    private var followingList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredFollowingChannels) { channel in
                    followingRow(channel: channel)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
    }

    private func followingRow(channel: LiveChannelItem) -> some View {
        let alreadyAdded = manager.sessions.contains { $0.channelId == channel.channelId }
            || recentlyAddedIds.contains(channel.channelId)
        let isAddingThis = addingChannelId == channel.channelId

        return Button {
            guard !alreadyAdded, !isAddingThis else { return }
            addChannel(channelId: channel.channelId)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 프로필 이미지
                AsyncImage(url: channel.channelImageUrl.flatMap { URL(string: $0) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    if channel.isLive {
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle().strokeBorder(DesignTokens.Colors.backgroundElevated, lineWidth: 1.5)
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.channelName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    if channel.isLive {
                        HStack(spacing: 6) {
                            if !channel.liveTitle.isEmpty {
                                Text(channel.liveTitle)
                                    .lineLimit(1)
                            }
                            if let cat = channel.categoryName, !cat.isEmpty {
                                Text("·")
                                Text(cat)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    } else {
                        Text("오프라인")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                // 시청자 수 (라이브인 경우)
                if channel.isLive && channel.viewerCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(DesignTokens.Typography.custom(size: 8))
                        Text(channel.formattedViewerCount)
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                // 추가 버튼
                addButtonLabel(isAdding: isAddingThis, alreadyAdded: alreadyAdded, isLive: channel.isLive)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded || isAddingThis || !manager.canAddSession || !channel.isLive)
        .opacity(alreadyAdded ? 0.5 : (channel.isLive ? 1.0 : 0.45))
    }

    private var followingEmptyView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "heart.slash")
                .font(DesignTokens.Typography.custom(size: 28, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            VStack(spacing: 4) {
                Text("팔로잉 채널이 없습니다")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("로그인 후 팔로잉한 채널이 여기에 표시됩니다")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    // MARK: - 검색 탭

    private var searchContent: some View {
        VStack(spacing: 0) {
            searchField
                .padding(DesignTokens.Spacing.md)

            if isSearching {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(DesignTokens.Colors.chzzkGreen)
                Spacer()
            } else if searchResults.isEmpty && channelSearchResults.isEmpty && hasSearched {
                Spacer()
                noResultsView
                Spacer()
            } else if !searchResults.isEmpty || !channelSearchResults.isEmpty {
                searchResultsList
            } else {
                Spacer()
                searchPromptView
                Spacer()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            TextField("채널명 또는 방송 제목으로 검색", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { performSearch() }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                    channelSearchResults = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // 라이브 결과
                if !searchResults.isEmpty {
                    sectionHeader("라이브 방송", count: searchResults.count)
                    ForEach(searchResults) { live in
                        liveSearchRow(live: live)
                    }
                }

                // 채널 결과
                if !channelSearchResults.isEmpty {
                    sectionHeader("채널", count: channelSearchResults.count)
                        .padding(.top, searchResults.isEmpty ? 0 : DesignTokens.Spacing.sm)
                    ForEach(channelSearchResults) { channel in
                        channelSearchRow(channel: channel)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("\(count)")
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5)))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var searchPromptView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "tv")
                .font(DesignTokens.Typography.custom(size: 28, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("채널명 또는 방송 제목으로 검색하세요")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            // 최근 검색어
            if !recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Text("최근 검색")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        Button {
                            withAnimation(DesignTokens.Animation.fast) { recentSearches.removeAll() }
                        } label: {
                            Text("지우기")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 6) {
                        ForEach(recentSearches, id: \.self) { query in
                            Button {
                                searchQuery = query
                            } label: {
                                Text(query)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.md)
            }
        }
    }

    private var noResultsView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.custom(size: 28, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("검색 결과가 없습니다")
                .font(.callout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("다른 검색어를 시도해보세요")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - 라이브 검색 결과 행

    private func liveSearchRow(live: LiveInfo) -> some View {
        let channelId = live.channel?.channelId ?? ""
        let alreadyAdded = manager.sessions.contains { $0.channelId == channelId }
            || recentlyAddedIds.contains(channelId)
        let isAddingThis = addingChannelId == channelId

        return Button {
            guard !channelId.isEmpty, !alreadyAdded, !isAddingThis else { return }
            addChannel(channelId: channelId)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 썸네일
                AsyncImage(url: live.liveImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Rectangle().fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                            .overlay {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                    }
                }
                .frame(width: 72, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // 채널 프로필
                AsyncImage(url: live.channel?.channelImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(live.channel?.channelName ?? "알 수 없음")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(live.liveTitle)
                            .lineLimit(1)
                        if let category = live.liveCategoryValue, !category.isEmpty {
                            Text("·")
                            Text(category)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                Spacer(minLength: 4)

                // 시청자 수
                HStack(spacing: 3) {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("\(live.concurrentUserCount)")
                        .font(.caption.weight(.medium).monospacedDigit())
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)

                addButtonLabel(isAdding: isAddingThis, alreadyAdded: alreadyAdded, isLive: true)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded || isAddingThis || !manager.canAddSession)
        .opacity(alreadyAdded ? 0.5 : 1.0)
    }

    // MARK: - 채널 검색 결과 행

    private func channelSearchRow(channel: ChannelInfo) -> some View {
        let channelId = channel.channelId
        let alreadyAdded = manager.sessions.contains { $0.channelId == channelId }
            || recentlyAddedIds.contains(channelId)
        let isAddingThis = addingChannelId == channelId

        return Button {
            guard !alreadyAdded, !isAddingThis else { return }
            addChannel(channelId: channelId)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                AsyncImage(url: channel.channelImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.channelName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    if channel.followerCount > 0 {
                        Text("팔로워 \(formatCount(channel.followerCount))")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                addButtonLabel(isAdding: isAddingThis, alreadyAdded: alreadyAdded, isLive: true)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded || isAddingThis || !manager.canAddSession)
        .opacity(alreadyAdded ? 0.5 : 1.0)
    }

    // MARK: - 공통 추가 버튼 라벨

    @ViewBuilder
    private func addButtonLabel(isAdding: Bool, alreadyAdded: Bool, isLive: Bool) -> some View {
        if isAdding {
            ProgressView()
                .controlSize(.small)
                .frame(width: 44)
        } else if alreadyAdded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .frame(width: 44)
        } else {
            Text("추가")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                .frame(width: 44)
        }
    }

    // MARK: - 직접 입력 탭

    private var directInputContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("채널 ID를 입력하여 직접 추가")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("치지직 채널 URL에서 채널 ID를 확인할 수 있습니다")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    TextField("채널 ID 입력", text: $channelIdInput)
                        .textFieldStyle(.plain)
                        .font(.callout.monospaced())
                        .onSubmit {
                            let id = channelIdInput.trimmingCharacters(in: .whitespaces)
                            guard !id.isEmpty else { return }
                            addChannel(channelId: id)
                        }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                }

                Button {
                    let id = channelIdInput.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    addChannel(channelId: id)
                } label: {
                    Group {
                        if addingChannelId != nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.chzzkGreen)
                .controlSize(.regular)
                .disabled(channelIdInput.trimmingCharacters(in: .whitespaces).isEmpty || addingChannelId != nil || !manager.canAddSession)
            }

            // 현재 세션 목록
            if !manager.sessions.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("현재 세션")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    ForEach(manager.sessions) { session in
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            AsyncImage(url: session.profileImageURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())

                            Text(session.channelName)
                                .font(.callout)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            statusBadge(for: session)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.lg)
    }

    @ViewBuilder
    private func statusBadge(for session: MultiLiveSession) -> some View {
        switch session.loadState {
        case .playing:
            HStack(spacing: 3) {
                Circle().fill(DesignTokens.Colors.chzzkGreen).frame(width: 5, height: 5)
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
        case .loading:
            ProgressView().controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .idle:
            Text("대기")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        case .offline:
            Image(systemName: "tv.slash")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - 에러 배너

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation(DesignTokens.Animation.fast) { addError = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(.orange.opacity(0.1))
        )
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func loadFollowingChannels() async {
        guard let apiClient = appState.apiClient else { return }
        isLoadingFollowing = true
        defer { isLoadingFollowing = false }
        do {
            let channels = try await apiClient.fetchFollowingChannels()
            withAnimation(DesignTokens.Animation.normal) {
                followingChannels = channels
            }
        } catch {
            withAnimation(DesignTokens.Animation.fast) { addError = "팔로잉 채널 로드 실패: \(error.localizedDescription)" }
        }
    }

    private func debounceSearch() {
        searchDebounceTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            channelSearchResults = []
            hasSearched = false
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    @MainActor
    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let apiClient = appState.apiClient else { return }
        isSearching = true
        addError = nil

        // 최근 검색어 추가 (최대 5개)
        if !recentSearches.contains(query) {
            recentSearches.insert(query, at: 0)
            if recentSearches.count > 5 { recentSearches.removeLast() }
        }

        Task {
            do {
                async let livesTask = apiClient.searchLives(keyword: query, size: 10)
                async let channelsTask = apiClient.searchChannels(keyword: query, size: 10)
                let (liveResult, channelResult) = try await (livesTask, channelsTask)
                withAnimation(DesignTokens.Animation.normal) {
                    searchResults = liveResult.data
                    channelSearchResults = channelResult.data
                    hasSearched = true
                }
            } catch {
                withAnimation(DesignTokens.Animation.normal) {
                    searchResults = []
                    channelSearchResults = []
                    hasSearched = true
                    addError = "검색 실패: \(error.localizedDescription)"
                }
            }
            isSearching = false
        }
    }

    private func addChannel(channelId: String) {
        addingChannelId = channelId
        addError = nil

        Task {
            await manager.addSession(channelId: channelId, preferredEngine: appState.settingsStore.player.preferredEngine)
            withAnimation(DesignTokens.Animation.snappy) {
                recentlyAddedIds.insert(channelId)
                addingChannelId = nil
            }
            channelIdInput = ""

            if !manager.canAddSession {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(DesignTokens.Animation.snappy) {
                    isPresented?.wrappedValue = false
                }
            }
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f만", Double(count) / 10_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f천", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
