// MARK: - MultiLiveAddSheet.swift
// CViewApp — 멀티라이브 채널 추가 시트
// 단일 페이지 통합 피커: 검색 + 팔로잉 + 채널 ID 직접 입력

import SwiftUI
import CViewCore
import CViewNetworking

struct MultiLiveAddSheet: View {

    @Bindable var manager: MultiLiveManager
    @Environment(AppState.self) private var appState
    var isPresented: Binding<Bool>?

    // 통합 검색 상태
    @State var searchQuery = ""
    @State var searchResults: [LiveInfo] = []
    @State var channelSearchResults: [ChannelInfo] = []
    @State var isSearching = false
    @State var hasSearched = false
    @State private var searchDebounceTask: Task<Void, Never>?

    // 팔로잉 상태
    @State var followingChannels: [LiveChannelItem] = []
    @State var isLoadingFollowing = false
    @State var showLiveOnly = true

    // 공통 상태
    @State private var channelIdInput = ""
    @State private var addError: String?
    @State var addingChannelId: String?
    @State var recentlyAddedIds: Set<String> = []
    @State private var showDirectInput = false

    /// 검색 모드 여부 (검색어가 있으면 검색 결과, 없으면 팔로잉)
    private var isSearchMode: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            mainContent
            if showDirectInput { directInputSection }
            if let error = addError { errorBanner(error) }
        }
        .onChange(of: searchQuery) { debounceSearch() }
        .task { await loadFollowingChannels() }
        .animation(DesignTokens.Animation.contentTransition, value: isSearchMode)
        .animation(DesignTokens.Animation.fast, value: showLiveOnly)
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
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
                    .scaleEffect(i < manager.sessions.count ? 1.0 : 0.7)
                    .shadow(
                        color: i < manager.sessions.count ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : .clear,
                        radius: 3
                    )
                    .animation(
                        DesignTokens.Animation.bouncy.delay(Double(i) * 0.06),
                        value: manager.sessions.count
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.6)))
    }

    // MARK: - 통합 검색바

    private var searchBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("채널명 또는 방송 제목 검색", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { performSearch() }
                if isSearching {
                    ProgressView().controlSize(.small)
                } else if !searchQuery.isEmpty {
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
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Colors.surfaceOverlay.opacity(0.5))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }

            // 라이브만 토글 (팔로잉 모드일 때만)
            if !isSearchMode {
                Button {
                    withAnimation(DesignTokens.Animation.fast) { showLiveOnly.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(showLiveOnly ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary.opacity(0.3))
                            .frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(showLiveOnly ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(
                            showLiveOnly
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.10)
                                : DesignTokens.Colors.surfaceOverlay.opacity(0.5)
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            showLiveOnly
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.22)
                                : DesignTokens.Glass.borderColor,
                            lineWidth: 0.5
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            // ID 직접입력 토글
            Button {
                withAnimation(DesignTokens.Animation.fast) { showDirectInput.toggle() }
            } label: {
                Image(systemName: "link")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(showDirectInput ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(showDirectInput
                                  ? DesignTokens.Colors.chzzkGreen.opacity(0.10)
                                  : DesignTokens.Colors.surfaceOverlay.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(
                                showDirectInput
                                    ? DesignTokens.Colors.chzzkGreen.opacity(0.22)
                                    : DesignTokens.Glass.borderColor,
                                lineWidth: 0.5
                            )
                    )
            }
            .buttonStyle(.plain)
            .help("채널 ID 직접 입력")

            // 새로고침
            if !isSearchMode {
                Button {
                    Task { await loadFollowingChannels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 30, height: 30)
                        .symbolEffect(.rotate, isActive: isLoadingFollowing)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingFollowing)
                .help("팔로잉 새로고침")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 메인 콘텐츠 (팔로잉 or 검색 결과)

    @ViewBuilder
    private var mainContent: some View {
        if isSearchMode {
            // 검색 모드
            if isSearching && searchResults.isEmpty && channelSearchResults.isEmpty {
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
            }
        } else {
            // 팔로잉 모드 (기본)
            if isLoadingFollowing && followingChannels.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .transition(.opacity)
                Spacer()
            } else if followingChannels.isEmpty {
                Spacer()
                followingEmptyView
                Spacer()
            } else if filteredFollowingChannels.isEmpty {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "tv.slash")
                        .font(DesignTokens.Typography.custom(size: 24, weight: .light))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .phaseAnimator([false, true]) { content, phase in
                            content
                                .scaleEffect(phase ? 1.06 : 1.0)
                                .opacity(phase ? 0.55 : 1.0)
                        } animation: { _ in
                            .easeInOut(duration: 2.0)
                        }
                    Text("라이브 중인 채널이 없습니다")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                Spacer()
            } else {
                followingList
            }
        }
    }

    // MARK: - 공통 추가 버튼 라벨

    @ViewBuilder
    func addButtonLabel(isAdding: Bool, alreadyAdded: Bool, isLive: Bool) -> some View {
        if isAdding {
            ProgressView()
                .controlSize(.small)
                .tint(DesignTokens.Colors.chzzkGreen)
                .frame(width: 52)
                .transition(.blurReplace)
        } else if alreadyAdded {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .symbolEffect(.bounce, options: .speed(1.5), value: alreadyAdded)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .frame(width: 52)
                .transition(.blurReplace)
        } else {
            Text("추가")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                .frame(width: 52)
                .transition(.blurReplace)
        }
    }

    // MARK: - 직접 입력 섹션 (접이식)

    private var directInputSection: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor)
                .frame(height: 0.5)

            HStack(spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    TextField("채널 ID 직접 입력", text: $channelIdInput)
                        .textFieldStyle(.plain)
                        .font(.callout.monospaced())
                        .onSubmit {
                            let id = channelIdInput.trimmingCharacters(in: .whitespaces)
                            guard !id.isEmpty else { return }
                            addChannel(channelId: id)
                        }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 8)
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
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.chzzkGreen)
                .controlSize(.regular)
                .disabled(channelIdInput.trimmingCharacters(in: .whitespaces).isEmpty || addingChannelId != nil || !manager.canAddSession)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
