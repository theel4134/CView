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
    @State var searchQuery = ""
    @State var searchResults: [LiveInfo] = []
    @State var channelSearchResults: [ChannelInfo] = []
    @State var isSearching = false
    @State var hasSearched = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State var recentSearches: [String] = []

    // 팔로잉 상태
    @State var followingChannels: [LiveChannelItem] = []
    @State var isLoadingFollowing = false
    @State var followingFilter: FollowingFilter = .all
    @State var followingSearchText = ""

    // 공통 상태
    @State private var channelIdInput = ""
    @State private var addError: String?
    @State var addingChannelId: String?
    @State var recentlyAddedIds: Set<String> = []
    @State private var selectedTab: AddSheetTab = .following

    private enum AddSheetTab: String, CaseIterable {
        case following = "라이브"
        case search = "검색"
        case direct = "채널 ID"
    }

    enum FollowingFilter: String, CaseIterable {
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
                tabButton(tab)
            }
        }
        .background(alignment: .bottom) {
            GeometryReader { geo in
                let tabWidth = geo.size.width / CGFloat(AddSheetTab.allCases.count)
                let index = AddSheetTab.allCases.firstIndex(of: selectedTab) ?? 0
                Capsule()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: tabWidth * 0.45, height: 2.5)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.3), radius: 3, y: 1)
                    .offset(x: tabWidth * CGFloat(index) + tabWidth * 0.275)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor)
                .frame(height: 0.5)
        }
    }

    private func tabButton(_ tab: AddSheetTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(DesignTokens.Animation.snappy) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Text(tab.rawValue)
                if tab == .following, !followingChannels.isEmpty {
                    Text("\(followingChannels.count)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5)))
                }
            }
            .font(DesignTokens.Typography.subhead.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 공통 추가 버튼 라벨

    @ViewBuilder
    func addButtonLabel(isAdding: Bool, alreadyAdded: Bool, isLive: Bool) -> some View {
        if isAdding {
            ProgressView()
                .controlSize(.small)
                .tint(DesignTokens.Colors.chzzkGreen)
                .frame(width: 52)
        } else if alreadyAdded {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            .frame(width: 52)
        } else {
            Text("추가")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                .frame(width: 52)
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
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.warning)
            Text(message)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(2)
            Spacer(minLength: DesignTokens.Spacing.xs)
            Button {
                withAnimation(DesignTokens.Animation.fast) { addError = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Colors.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Colors.warning.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    func loadFollowingChannels() async {
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
            performSearch()
        }
    }

    @MainActor
    func performSearch() {
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

    func addChannel(channelId: String) {
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

    func formatCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f만", Double(count) / 10_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f천", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
