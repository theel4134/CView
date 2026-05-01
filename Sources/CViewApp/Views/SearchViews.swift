// MARK: - SearchViews.swift
// CViewApp - 검색 뷰 (프리미엄 디자인)
// Design: Spotlight/Raycast 스타일 검색 + 모던 결과 카드

import CViewCore
import CViewUI
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

// MARK: - Search View

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel: SearchViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // [Top chrome 2026-05-01] hiddenTitleBar 환경에서 검색 바 위로 macOS
            // 트래픽 라이트가 올라오는 문제 해결 — 28pt 드래그 영역 확보.
            Color.clear
                .frame(height: 28)
            if let vm = viewModel {
                SearchContentView(viewModel: vm)
                    .task(id: appState.homeViewModel?.followingChannels.count) {
                        if let homeVM = appState.homeViewModel {
                            vm.followingChannelNames = homeVM.followingChannels.map(\.channelName)
                        }
                    }
                    // [Redesign 2026-04-29] router에서 들어온 pending query 소비
                    .task(id: router.pendingSearchQuery) {
                        await consumePendingQuery(vm: vm)
                    }
            } else {
                ProgressView()
                    .onAppear {
                        if let apiClient = appState.apiClient {
                            let vm = SearchViewModel(apiClient: apiClient)
                            // 팔로잉 채널명 주입 (자동완성 용)
                            if let homeVM = appState.homeViewModel {
                                vm.followingChannelNames = homeVM.followingChannels.map(
                                    \.channelName)
                            }
                            viewModel = vm
                            // VM 생성 직후에도 pending query 즉시 적용
                            Task { await consumePendingQuery(vm: vm) }
                        }
                    }
            }
        }
        .contentBackground()
    }

    /// router.pendingSearchQuery를 검색 VM에 적용하고 비운다.
    @MainActor
    private func consumePendingQuery(vm: SearchViewModel) async {
        guard let pending = router.pendingSearchQuery, !pending.isEmpty else { return }
        // 동일 query면 재검색 생략
        if vm.query.trimmingCharacters(in: .whitespaces) != pending {
            vm.query = pending
        }
        router.pendingSearchQuery = nil
    }
}

struct SearchContentView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var isSearchBarFocused = false
    @State private var selectedClip: ClipInfo?
    @State private var selectedChannelId: String?
    /// [Redesign 2026-04-29] 빠른 액션 결과 toast/오류 메시지
    @State private var actionMessage: String?
    @State private var actionMessageId = UUID()

    var body: some View {
        HStack(spacing: 0) {
            // 왼쪽: 검색 리스트
            searchListContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 오른쪽: 채널 상세 패널 (push-left 슬라이드)
            if let channelId = selectedChannelId {
                Divider()

                channelDetailPanel(channelId: channelId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(DesignTokens.Animation.contentTransition, value: selectedChannelId)
        .overlay(alignment: .bottom) {
            // [Redesign 2026-04-29] 빠른 액션 결과 toast
            if let actionMessage {
                Text(actionMessage)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                    }
                    .shadow(DesignTokens.Shadow.control)
                    .padding(.bottom, DesignTokens.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(actionMessageId)
            }
        }
        .animation(DesignTokens.Animation.fast, value: actionMessage)
    }

    // MARK: - Live Row Builder (with quick actions)

    /// [Redesign 2026-04-29] 라이브 결과 행을 빠른 액션과 함께 생성한다.
    @ViewBuilder
    private func liveResultRow(_ live: LiveInfo) -> some View {
        let channelId = live.channel?.channelId
        let isInMultiLive =
            channelId.map { id in
                appState.multiLiveManager.sessions.contains(where: { $0.channelId == id })
            } ?? false
        let isInMultiChat =
            channelId.map { id in
                appState.followingViewState.chatSessionManager.sessions.contains(where: {
                    $0.id == id
                })
            } ?? false

        EquatableSearchLiveRow(
            live: live,
            onAddMultiLive: channelId.map { id in
                {
                    Task {
                        await addLiveToMultiLive(
                            channelId: id, channelName: live.channel?.channelName)
                    }
                }
            },
            onAddMultiChat: channelId.map { id in
                {
                    Task {
                        await addLiveToMultiChat(
                            channelId: id, channelName: live.channel?.channelName)
                    }
                }
            },
            onOpenChannel: channelId.map { id in
                { selectedChannelId = id }
            },
            onCopyLink: channelId.map { id in
                {
                    #if canImport(AppKit)
                        let url = "https://chzzk.naver.com/live/\(id)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        showActionMessage("링크 복사됨")
                    #endif
                }
            },
            isAlreadyInMultiLive: isInMultiLive,
            isAlreadyInMultiChat: isInMultiChat
        )
        .equatable()
        .contentShape(Rectangle())
        .onTapGesture {
            if let chId = channelId {
                router.navigate(to: .live(channelId: chId))
            }
        }
    }

    // MARK: - Quick Action Handlers

    private func addLiveToMultiLive(channelId: String, channelName: String?) async {
        let mlm = appState.multiLiveManager
        if mlm.sessions.contains(where: { $0.channelId == channelId }) {
            showActionMessage("이미 멀티라이브에 추가됨")
            return
        }
        guard mlm.canAddSession else {
            showActionMessage("멀티라이브 최대 세션 수에 도달했습니다")
            return
        }
        await mlm.addSession(channelId: channelId, presentationOverride: .embedded)
        showActionMessage("멀티라이브에 \(channelName ?? channelId) 추가됨")
    }

    private func addLiveToMultiChat(channelId: String, channelName: String?) async {
        let manager = appState.followingViewState.chatSessionManager
        if manager.sessions.contains(where: { $0.id == channelId }) {
            showActionMessage("이미 멀티채팅에 추가됨")
            return
        }
        guard manager.canAddSession else {
            showActionMessage("멀티채팅 최대 세션 수에 도달했습니다")
            return
        }
        guard let apiClient = appState.apiClient else { return }
        do {
            let liveDetail = try await apiClient.liveDetail(channelId: channelId)
            guard let chatChannelId = liveDetail.chatChannelId else {
                showActionMessage("\(channelName ?? channelId)은(는) 현재 방송 중이 아닙니다")
                return
            }
            let tokenInfo = try await apiClient.chatAccessToken(chatChannelId: chatChannelId)
            let resolvedName = liveDetail.channel?.channelName ?? channelName ?? channelId
            let chatUid: String?
            if appState.isLoggedIn,
                let userInfo = try? await apiClient.userStatus()
            {
                chatUid = userInfo.userIdHash ?? appState.userChannelId
            } else {
                chatUid = appState.userChannelId
            }
            let result = await manager.addSession(
                channelId: channelId,
                channelName: resolvedName,
                chatChannelId: chatChannelId,
                accessToken: tokenInfo.accessToken,
                extraToken: tokenInfo.extraToken,
                uid: chatUid,
                nickname: appState.userNickname
            )
            switch result {
            case .alreadyExists:
                showActionMessage("이미 멀티채팅에 추가됨")
            case .maxSessionsReached:
                showActionMessage("멀티채팅 최대 세션 수에 도달했습니다")
            case .success, .connectionFailed:
                showActionMessage("멀티채팅에 \(resolvedName) 추가됨")
            }
        } catch {
            showActionMessage("멀티채팅 추가 실패: \(error.localizedDescription)")
        }
    }

    private func showActionMessage(_ message: String) {
        actionMessage = message
        actionMessageId = UUID()
        let id = actionMessageId
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if id == actionMessageId {
                actionMessage = nil
            }
        }
    }

    // MARK: - Search List Content

    private var searchListContent: some View {
        VStack(spacing: 0) {
            // Premium search bar
            searchBar

            // Autocomplete suggestions dropdown
            if viewModel.showAutocomplete && !viewModel.autocompleteSuggestions.isEmpty {
                autocompleteDropdown
            }

            // Tab picker
            tabPicker

            // Results
            let allSearching =
                viewModel.isSearchingChannels && viewModel.isSearchingLives
                && viewModel.isSearchingVideos && viewModel.isSearchingClips
            let allEmpty =
                viewModel.channelResults.isEmpty && viewModel.liveResults.isEmpty
                && viewModel.videoResults.isEmpty && viewModel.clipResults.isEmpty
            if allSearching && allEmpty {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("검색 중...")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                ErrorStateView(message: error) {
                    Task { await viewModel.performSearch() }
                }
                Spacer()
            } else if viewModel.query.isEmpty {
                searchEmptyPrompt
            } else {
                searchResultsList
            }
        }
    }

    // MARK: - Channel Detail Panel

    @ViewBuilder
    private func channelDetailPanel(channelId: String) -> some View {
        VStack(spacing: 0) {
            // 패널 헤더: 닫기 버튼
            HStack {
                Button {
                    selectedChannelId = nil
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(DesignTokens.Typography.captionSemibold)
                        Text("검색 결과")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    router.navigate(to: .channelDetail(channelId: channelId))
                    selectedChannelId = nil
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text("전체 화면")
                            .font(DesignTokens.Typography.captionMedium)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(DesignTokens.Typography.caption)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surfaceBase)

            Divider()

            ChannelInfoView(channelId: channelId)
                .id(channelId)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.subhead)
                .foregroundStyle(
                    isSearchBarFocused
                        ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)

            TextField("채널, 라이브, 비디오 검색...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.custom(size: 15))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .onSubmit { Task { await viewModel.performSearch() } }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            DesignTokens.Colors.surfaceElevated,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(
                    isSearchBarFocused
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.5)
                        : DesignTokens.Glass.borderColorLight,
                    lineWidth: isSearchBarFocused ? 1.5 : 0.5
                )
        }
        .shadow(
            color: isSearchBarFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.1) : .clear,
            radius: 8
        )
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .animation(DesignTokens.Animation.fast, value: isSearchBarFocused)
        .animation(DesignTokens.Animation.micro, value: viewModel.query.isEmpty)
    }

    // MARK: - Autocomplete Dropdown

    private var autocompleteDropdown: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.autocompleteSuggestions) { suggestion in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: suggestion.kind == .recent ? "clock" : "person.circle")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(
                            suggestion.kind == .recent
                                ? DesignTokens.Colors.textTertiary
                                : DesignTokens.Colors.chzzkGreen
                        )
                        .frame(width: 18)

                    Text(suggestion.text)
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if suggestion.kind == .following {
                        Text("팔로잉")
                            .font(DesignTokens.Typography.microSemibold)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // 검색어에 삽입 버튼
                    Button {
                        viewModel.query = suggestion.text
                    } label: {
                        Image(systemName: "arrow.up.left")
                            .font(DesignTokens.Typography.footnoteMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.query = suggestion.text
                    Task { await viewModel.performSearch() }
                }
                .background(Color.clear)

                if suggestion.id != viewModel.autocompleteSuggestions.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(
            DesignTokens.Colors.surfaceBase,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .shadow(color: DesignTokens.Colors.background.opacity(0.5), radius: 6, y: 4)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(DesignTokens.Animation.fast, value: viewModel.autocompleteSuggestions.count)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            // [Redesign 2026-04-29] `전체`(통합 결과) scope 추가
            ForEach(SearchScope.allCases) { scope in
                SearchTabButton(
                    title: scope.title,
                    icon: scope.icon,
                    isSelected: viewModel.selectedScope == scope,
                    count: tabCount(for: scope)
                ) {
                    Task { await viewModel.onScopeChanged(scope) }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    private func tabCount(for scope: SearchScope) -> Int {
        switch scope {
        case .all:
            return viewModel.channelResults.count
                + viewModel.liveResults.count
                + viewModel.videoResults.count
                + viewModel.clipResults.count
        case .channel: return viewModel.channelResults.count
        case .live: return viewModel.liveResults.count
        case .video: return viewModel.videoResults.count
        case .clip: return viewModel.clipResults.count
        }
    }

    private func tabTitle(for tab: SearchType) -> String {
        switch tab {
        case .channel: "채널"
        case .live: "라이브"
        case .video: "비디오"
        case .clip: "클립"
        }
    }

    private func tabIcon(for tab: SearchType) -> String {
        switch tab {
        case .channel: "person.2"
        case .live: "play.tv"
        case .video: "film"
        case .clip: "film.stack"
        }
    }

    // MARK: - Empty Prompt

    private var searchEmptyPrompt: some View {
        VStack(spacing: 0) {
            if !viewModel.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("최근 검색어")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        Button("전체 삭제") { viewModel.clearRecentSearches() }
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xs)

                    ForEach(viewModel.recentSearches, id: \.self) { term in
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "clock")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text(term)
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Spacer()
                            Button {
                                viewModel.removeRecentSearch(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.query = term
                            Task { await viewModel.performSearch() }
                        }
                    }

                    Divider()
                        .padding(.top, DesignTokens.Spacing.sm)
                }
            }

            VStack(spacing: DesignTokens.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                        .frame(width: 80, height: 80)

                    Image(systemName: "magnifyingglass")
                        .font(DesignTokens.Typography.custom(size: 30))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.6))
                }

                VStack(spacing: DesignTokens.Spacing.xs) {
                    Text("검색어를 입력하세요")
                        .font(DesignTokens.Typography.custom(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    Text("채널명, 라이브 방송, 비디오, 클립을 검색할 수 있습니다")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch viewModel.selectedScope {
                case .all:
                    topResultsContent
                case .channel:
                    if viewModel.channelResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingChannels {
                            tabLoadingView
                        } else {
                            searchEmptyState("채널")
                        }
                    } else {
                        ForEach(viewModel.channelResults) { channel in
                            EquatableSearchChannelRow(channel: channel)
                                .equatable()
                                .contentShape(Rectangle())
                                .background(
                                    selectedChannelId == channel.channelId
                                        ? DesignTokens.Colors.chzzkGreen.opacity(0.08)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                )
                                .onTapGesture {
                                    if selectedChannelId == channel.channelId {
                                        selectedChannelId = nil
                                    } else {
                                        selectedChannelId = channel.channelId
                                    }
                                }
                                .onAppear {
                                    if channel.id == viewModel.channelResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }

                case .live:
                    if viewModel.liveResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingLives {
                            tabLoadingView
                        } else {
                            searchEmptyState("라이브")
                        }
                    } else {
                        if !viewModel.liveResults.isEmpty {
                            HStack {
                                Spacer()
                                Picker("", selection: $viewModel.liveSortOption) {
                                    ForEach(LiveSortOption.allCases, id: \.self) { opt in
                                        Text(opt.rawValue).tag(opt)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                                .padding(.horizontal, DesignTokens.Spacing.lg)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                            }
                        }
                        ForEach(viewModel.liveResults) { live in
                            liveResultRow(live)
                                .onAppear {
                                    if live.id == viewModel.liveResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }

                case .video:
                    if viewModel.videoResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingVideos {
                            tabLoadingView
                        } else {
                            searchEmptyState("비디오")
                        }
                    } else {
                        ForEach(viewModel.videoResults) { video in
                            EquatableSearchVideoRow(video: video)
                                .equatable()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    router.navigate(to: .vod(videoNo: video.videoNo))
                                }
                                .onAppear {
                                    if video.id == viewModel.videoResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }

                case .clip:
                    if viewModel.clipResults.isEmpty && !viewModel.query.isEmpty {
                        if viewModel.isSearchingClips {
                            tabLoadingView
                        } else {
                            searchEmptyState("클립")
                        }
                    } else {
                        ForEach(viewModel.clipResults) { clip in
                            EquatableSearchClipRow(clip: clip)
                                .equatable()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedClip = clip
                                }
                                .onAppear {
                                    if clip.id == viewModel.clipResults.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }
                    }
                }

                if viewModel.isSearching && !viewModel.query.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
        }
        .sheet(item: $selectedClip) { clip in
            ClipPlayerView(clipInfo: clip)
                .frame(minWidth: 640, minHeight: 400)
        }
    }

    private var tabLoadingView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: DesignTokens.Spacing.md) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .frame(width: 100, height: 56)
                        .shimmer()
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(height: 12)
                            .shimmer()
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 80, height: 10)
                            .shimmer()
                    }
                    Spacer()
                }
                .padding(DesignTokens.Spacing.sm)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func searchEmptyState(_ type: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(DesignTokens.Typography.display)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("\(type) 검색 결과가 없습니다")
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Top Results (전체 scope)

    /// [Redesign 2026-04-29] `전체` scope에서 보여주는 통합 결과 화면.
    /// 각 bucket의 상위 N개를 section별로 표시하고, 더보기로 해당 scope로 전환된다.
    @ViewBuilder
    private var topResultsContent: some View {
        let allEmpty =
            viewModel.channelResults.isEmpty
            && viewModel.liveResults.isEmpty
            && viewModel.videoResults.isEmpty
            && viewModel.clipResults.isEmpty
        let anySearching =
            viewModel.isSearchingChannels
            || viewModel.isSearchingLives
            || viewModel.isSearchingVideos
            || viewModel.isSearchingClips

        if allEmpty && anySearching {
            tabLoadingView
        } else if allEmpty && !viewModel.query.isEmpty {
            searchEmptyState("통합")
        } else {
            // 라이브 (가장 시급한 결과 → 상단)
            topResultsSection(
                title: "라이브",
                icon: "play.tv",
                count: viewModel.liveResults.count,
                isLoading: viewModel.isSearchingLives,
                error: viewModel.bucketErrors[.live],
                jumpScope: .live
            ) {
                ForEach(viewModel.liveResults.prefix(3)) { live in
                    liveResultRow(live)
                }
            }

            // 채널
            topResultsSection(
                title: "채널",
                icon: "person.2",
                count: viewModel.channelResults.count,
                isLoading: viewModel.isSearchingChannels,
                error: viewModel.bucketErrors[.channel],
                jumpScope: .channel
            ) {
                ForEach(viewModel.channelResults.prefix(3)) { channel in
                    EquatableSearchChannelRow(channel: channel)
                        .equatable()
                        .contentShape(Rectangle())
                        .background(
                            selectedChannelId == channel.channelId
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.08)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        )
                        .onTapGesture {
                            if selectedChannelId == channel.channelId {
                                selectedChannelId = nil
                            } else {
                                selectedChannelId = channel.channelId
                            }
                        }
                }
            }

            // 비디오
            topResultsSection(
                title: "비디오",
                icon: "film",
                count: viewModel.videoResults.count,
                isLoading: viewModel.isSearchingVideos,
                error: viewModel.bucketErrors[.video],
                jumpScope: .video
            ) {
                ForEach(viewModel.videoResults.prefix(3)) { video in
                    EquatableSearchVideoRow(video: video)
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.navigate(to: .vod(videoNo: video.videoNo))
                        }
                }
            }

            // 클립 (전역 검색 API 부재 — 관련 채널 클립 한정)
            topResultsSection(
                title: "관련 채널 클립",
                icon: "film.stack",
                count: viewModel.clipResults.count,
                isLoading: viewModel.isSearchingClips,
                error: viewModel.bucketErrors[.clip],
                jumpScope: .clip,
                footnote: "Chzzk에 전역 클립 검색 API가 없어 상위 채널 클립을 제목으로 필터링합니다."
            ) {
                ForEach(viewModel.clipResults.prefix(3)) { clip in
                    EquatableSearchClipRow(clip: clip)
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedClip = clip
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func topResultsSection<Content: View>(
        title: String,
        icon: String,
        count: Int,
        isLoading: Bool,
        error: String?,
        jumpScope: SearchScope,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // 모든 bucket이 비어 있고 로딩도 아닌 경우 section 자체를 숨겨 화면을 깔끔하게
        if count > 0 || isLoading || error != nil {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: icon)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text(title)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if count > 0 {
                        Text("\(count)")
                            .font(DesignTokens.Typography.microSemibold)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                    }
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Spacer()
                    if count > 3 {
                        Button("더보기") {
                            Task { await viewModel.onScopeChanged(jumpScope) }
                        }
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.xs)

                if let error {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }

                content()

                if let footnote, count > 0 {
                    Text(footnote)
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)
                }

                Divider()
                    .padding(.top, DesignTokens.Spacing.xs)
            }
        }
    }
}
