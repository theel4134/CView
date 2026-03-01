// MARK: - MultiLiveAddSheet.swift
import SwiftUI
import CViewCore
import CViewNetworking
import CViewUI

// MARK: - Add Channel Sheet  (슬라이드 패널 / 모달 양쪽 모두 사용 가능)
struct MLAddChannelSheet: View {
    let manager: MultiLiveSessionManager
    let appState: AppState
    let onError: (String) -> Void
    /// 닫기 동작 — 슬라이드 패널 모드에서는 binding을 직접 내려줍니다
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var envDismiss
    private func dismiss() {
        if let onDismiss { onDismiss() } else { envDismiss() }
    }

    enum AddTab { case following, search }
    @State private var selectedTab: AddTab = .following
    @State private var searchQuery = ""
    @State private var searchResults: [ChannelInfo] = []
    @State private var isSearching = false
    @State private var followingLive: [LiveChannelItem] = []
    @State private var followingOffline: [MLFollowingEntry] = []
    @State private var isLoadingFollowing = false
    @State private var followingLoadError: String?
    @State private var isAddingChannelIds: Set<String> = []
    @State private var debounceTask: Task<Void, Never>?

    private var isFull: Bool { manager.sessions.count >= MultiLiveSessionManager.maxSessions }
    /// O(1) 세션 포함 여부 확인 — 각 행의 O(n) contains 호출 대체
    private var addedChannelIds: Set<String> { Set(manager.sessions.map(\.channelId)) }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            capacityBar
            segmentBar
            Divider().overlay(.white.opacity(DesignTokens.Glass.borderOpacityLight))
            Group {
                switch selectedTab {
                case .following: followingContent
                case .search:    searchContent
                }
            }
            .animation(DesignTokens.Animation.fast, value: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background.opacity(0.85))
        .background(.ultraThinMaterial)
        .onAppear { Task { await loadFollowing() } }
    }

    // MARK: Header
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("채널 추가")
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(isFull ? "최대 채널 수에 도달했습니다" : "채널을 선택해 동시에 시청하세요")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(isFull ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                    .animation(DesignTokens.Animation.fast, value: isFull)
            }
            Spacer()
            Button { dismiss() } label: {
                Text("완료")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                        .overlay(Capsule().stroke(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, DesignTokens.Spacing.md)
    }

    // MARK: Capacity Bar
    private var capacityBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<MultiLiveSessionManager.maxSessions, id: \.self) { i in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(i < manager.sessions.count
                          ? DesignTokens.Colors.chzzkGreen
                          : Color.white.opacity(0.1))
                    .frame(height: 3)
                    .animation(DesignTokens.Animation.snappy, value: manager.sessions.count)
            }
            Text("\(manager.sessions.count)/\(MultiLiveSessionManager.maxSessions)")
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(isFull ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                .frame(minWidth: 28, alignment: .trailing)
                .animation(DesignTokens.Animation.fast, value: isFull)
        }
        .padding(.horizontal, 18).padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: Segment Bar
    private var segmentBar: some View {
        HStack(spacing: 0) {
            segmentBtn("팔로잉 라이브", tab: .following)
            segmentBtn("채널 검색", tab: .search)
        }
        .padding(.horizontal, 18).padding(.bottom, DesignTokens.Spacing.xxs)
    }

    @ViewBuilder
    private func segmentBtn(_ label: String, tab: AddTab) -> some View {
        let sel = selectedTab == tab
        Button { withAnimation(DesignTokens.Animation.fast) { selectedTab = tab } } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 13, weight: sel ? .semibold : .regular))
                    .foregroundStyle(sel ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                Rectangle()
                    .fill(sel ? DesignTokens.Colors.chzzkGreen : Color.clear)
                    .frame(height: 2).clipShape(Capsule())
            }
        }
        .buttonStyle(.plain).frame(maxWidth: .infinity)
    }

    // MARK: Following Content
    @ViewBuilder
    private var followingContent: some View {
        if !appState.isLoggedIn {
            notLoggedInView
        } else if isLoadingFollowing && followingLive.isEmpty && followingOffline.isEmpty {
            loadingView(text: "팔로잉 채널 불러오는 중...")
        } else if let error = followingLoadError, followingLive.isEmpty && followingOffline.isEmpty {
            errorView(error) { Task { await loadFollowing() } }
        } else if followingLive.isEmpty && followingOffline.isEmpty {
            emptyFollowingView
        } else {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if !followingLive.isEmpty {
                            Section {
                                // 라이브 채널: 2열 썸네일 카드 그리드
                                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(followingLive) { item in
                                        let cid = item.channelId
                                        MLLiveChannelCard(
                                            item: item,
                                            isAlreadyAdded: addedChannelIds.contains(cid),
                                            isAdding: isAddingChannelIds.contains(cid),
                                            isFull: isFull,
                                            onAdd: { Task { await addChannelById(cid) } }
                                        )
                                    }
                                }
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                            } header: {
                                sectionHeader(
                                    dot: DesignTokens.Colors.chzzkGreen,
                                    title: "방송 중",
                                    count: followingLive.count
                                )
                            }
                        }
                        if !followingOffline.isEmpty {
                            Section {
                                ForEach(followingOffline) { entry in
                                    let cid = entry.channelId
                                    MLChannelRowView(
                                        channelId:      cid,
                                        channelName:    entry.channelName,
                                        imageURL:       entry.imageURL,
                                        isVerified:     entry.isVerified,
                                        isLive:         false,
                                        isOffline:      true,
                                        followerCount:  nil,
                                        isAlreadyAdded: addedChannelIds.contains(cid),
                                        isAdding:       isAddingChannelIds.contains(cid),
                                        isFull:         isFull,
                                        onAdd:          { Task { await addChannelById(cid) } }
                                    )
                                    .equatable()
                                }
                            } header: {
                                sectionHeader(
                                    dot: DesignTokens.Colors.textTertiary.opacity(0.5),
                                    title: "오프라인",
                                    count: followingOffline.count
                                )
                            }
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    if isLoadingFollowing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.65).tint(DesignTokens.Colors.chzzkGreen)
                            Text("불러오는 중...")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                    }
                }
                // 새로고침 버튼 (우상단)
                Button { Task { await loadFollowing() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .rotationEffect(.degrees(isLoadingFollowing ? 360 : 0))
                        .animation(
                            isLoadingFollowing
                                ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                                : .linear(duration: 0),
                            value: isLoadingFollowing
                        )
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay { Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5) }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingFollowing)
                .padding(.top, DesignTokens.Spacing.xs).padding(.trailing, DesignTokens.Spacing.sm)
            }
        }
    }

    private func sectionHeader(dot: Color, title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(title)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("\(count)")
                .font(DesignTokens.Typography.custom(size: 11, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.sm)
        .background(.thinMaterial)
    }

    // MARK: Search Content
    @ViewBuilder
    private var searchContent: some View {
        VStack(spacing: 0) {
            searchBar
            if isSearching {
                loadingView(text: "검색 중...")
            } else if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(searchResults) { ch in
                            let cid = ch.channelId
                            MLChannelRowView(
                                channelId:      cid,
                                channelName:    ch.channelName,
                                imageURL:       ch.channelImageURL,
                                isVerified:     ch.verifiedMark,
                                isLive:         false,
                                isOffline:      false,
                                followerCount:  ch.followerCount > 0 ? ch.followerCount : nil,
                                isAlreadyAdded: addedChannelIds.contains(cid),
                                isAdding:       isAddingChannelIds.contains(cid),
                                isFull:         isFull,
                                onAdd:          { Task { await addChannelById(cid) } }
                            )
                            .equatable()
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, DesignTokens.Spacing.xs)
                }
            } else {
                searchEmptyState
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchQuery.isEmpty
                                 ? DesignTokens.Colors.textTertiary
                                 : DesignTokens.Colors.chzzkGreen)
                .font(DesignTokens.Typography.captionMedium)
                .animation(DesignTokens.Animation.fast, value: searchQuery.isEmpty)

            TextField("채널명 또는 채널 ID 검색", text: $searchQuery)
                .textFieldStyle(.plain).font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .onSubmit { Task { await performSearch() } }
                .onChange(of: searchQuery) { _, new in
                    debounceTask?.cancel()
                    if new.isEmpty { searchResults = []; return }
                    debounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        await performSearch()
                    }
                }

            if isSearching {
                ProgressView().scaleEffect(0.65).tint(DesignTokens.Colors.chzzkGreen)
            } else if !searchQuery.isEmpty {
                Button { searchQuery = ""; searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                        .font(DesignTokens.Typography.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(searchQuery.isEmpty
                            ? .white.opacity(DesignTokens.Glass.borderOpacityLight)
                            : DesignTokens.Colors.chzzkGreen.opacity(0.35),
                            lineWidth: searchQuery.isEmpty ? 0.5 : 1))
        )
        .shadow(color: searchQuery.isEmpty ? .clear : DesignTokens.Colors.chzzkGreen.opacity(0.08), radius: 6)
        .padding(.horizontal, DesignTokens.Spacing.md).padding(.top, DesignTokens.Spacing.sm).padding(.bottom, DesignTokens.Spacing.xs)
        .animation(DesignTokens.Animation.fast, value: searchQuery.isEmpty)
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        VStack(spacing: 18) {
            if searchQuery.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.custom(size: 36)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.35))
                Text("채널명을 검색하세요")
                    .font(DesignTokens.Typography.captionMedium).foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                Image(systemName: "exclamationmark.magnifyingglass")
                    .font(DesignTokens.Typography.custom(size: 36)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.35))
                VStack(spacing: 4) {
                    Text("검색 결과가 없습니다")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .medium)).foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("\"\(searchQuery)\"")
                        .font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                // 채널 ID 직접 추가
                if !isFull && !manager.sessions.contains(where: { $0.channelId == searchQuery }) {
                    VStack(spacing: 8) {
                        Text("채널 ID로 직접 추가")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
                        let isAdding = isAddingChannelIds.contains(trimmed)
                        Button {
                            Task { await addChannelById(trimmed) }
                        } label: {
                            HStack(spacing: 6) {
                                if isAdding {
                                    ProgressView().scaleEffect(0.65).tint(.black)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "plus").font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                                }
                                Text(trimmed)
                                    .font(DesignTokens.Typography.captionSemibold)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(DesignTokens.Colors.onPrimary)
                            .padding(.horizontal, 18).padding(.vertical, DesignTokens.Spacing.sm)
                            .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                        }
                        .buttonStyle(.plain)
                        .disabled(isAdding)
                    }
                    .padding(.top, DesignTokens.Spacing.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Utility Views
    @ViewBuilder
    private func loadingView(text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().tint(DesignTokens.Colors.chzzkGreen)
            Text(text).font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(_ message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(DesignTokens.Typography.custom(size: 32)).foregroundStyle(.orange.opacity(0.75))
            Text(message)
                .font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Button(action: onRetry) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise").font(DesignTokens.Typography.captionSemibold)
                    Text("다시 시도").font(DesignTokens.Typography.captionSemibold)
                }
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.xs)
                .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var notLoggedInView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(DesignTokens.Typography.custom(size: 38)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
            Text("로그인이 필요합니다")
                .font(DesignTokens.Typography.bodySemibold).foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("팔로잉 목록을 보려면 로그인이 필요합니다.\n채널 검색에서 직접 추가할 수 있습니다.")
                .font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Button { withAnimation { selectedTab = .search } } label: {
                Text("채널 검색으로 이동")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Capsule().stroke(DesignTokens.Colors.chzzkGreen.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, DesignTokens.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyFollowingView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(DesignTokens.Typography.custom(size: 36)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.45))
            Text("팔로잉 채널이 없습니다")
                .font(DesignTokens.Typography.custom(size: 13, weight: .medium)).foregroundStyle(DesignTokens.Colors.textSecondary)
            Button { withAnimation { selectedTab = .search } } label: {
                Text("채널 검색으로 이동")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Capsule().stroke(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data Loading

    /// fetchFollowingChannels()로 팔로잉 채널 + 라이브 상세(썸네일/시청자수)를 한 번에 조회합니다.
    private func loadFollowing() async {
        guard let apiClient = appState.apiClient, appState.isLoggedIn else { return }
        isLoadingFollowing = true
        followingLoadError = nil
        followingLive    = []
        followingOffline = []
        defer { isLoadingFollowing = false }

        do {
            let allChannels = try await apiClient.fetchFollowingChannels()
            followingLive = allChannels.filter { $0.isLive }
            followingOffline = allChannels.filter { !$0.isLive }.map { ch in
                MLFollowingEntry(
                    id:          ch.channelId,
                    channelId:   ch.channelId,
                    channelName: ch.channelName,
                    imageURL:    ch.channelImageUrl.flatMap { URL(string: $0) },
                    isLive:      false,
                    isVerified:  false
                )
            }
        } catch {
            if followingLive.isEmpty && followingOffline.isEmpty {
                followingLoadError = "팔로잉 목록을 불러오지 못했습니다"
            }
        }
    }

    private func performSearch() async {
        guard let apiClient = appState.apiClient, !searchQuery.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await apiClient.searchChannels(keyword: searchQuery, size: 20)
            searchResults = results.data
        } catch { searchResults = [] }
    }

    private func addChannelById(_ channelId: String) async {
        let trimmed = channelId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let preferredEngine = appState.settingsStore.player.preferredEngine
        guard let session = await manager.addSession(channelId: trimmed, preferredEngine: preferredEngine) else {
            onError("이미 추가된 채널이거나 최대 개수(4)에 도달했습니다."); return
        }
        guard let apiClient = appState.apiClient else {
            onError("API 클라이언트가 초기화되지 않았습니다."); return
        }
        isAddingChannelIds.insert(trimmed)
        let paneCount = manager.sessions.count
        let apiRef = apiClient
        let appRef = appState
        // [멀티라이브 먹통 방지] 세션 시작을 비동기 분리.
        // await session.start()는 API 호출 + VLC 초기화 + view mount 대기(최대 5초)를
        // 포함하여 MainActor를 장시간 점유한다.
        // 여러 채널을 빠르게 추가하면 동시에 여러 start()가 MainActor에서 경쟁하면서
        // SwiftUI 업데이트를 차단하여 앱이 먹통이 된다.
        // fire-and-forget으로 분리하면 addChannelById()가 즉시 반환되어
        // UI가 응답성을 유지하고, 각 세션은 자체 로딩 상태를 표시한다.
        let onErrorCb = onError
        session.startTask = Task {
            await session.start(using: apiRef, appState: appRef, paneCount: paneCount)
            // 세션 시작 실패 시 사용자에게 에러 피드백 제공
            if case .error(let msg) = session.loadState {
                onErrorCb("채널 시작 실패: \(msg)")
            }
        }
        // addSession 완료 즉시 로딩 표시 해제 (세션 자체 loadState가 UI 표시 담당)
        isAddingChannelIds.remove(trimmed)
        if isFull {
            withAnimation(DesignTokens.Animation.contentTransition) { dismiss() }
        }
    }
}

// MARK: - Channel Row
// 독립 struct 으로 분리해 SwiftUI 구조적 diff + .equatable() 최적화 활용.
// isAlreadyAdded / isAdding / isFull 이 변하지 않으면 body 평가를 완전히 스킵함.
private struct MLChannelRowView: View, Equatable {
    let channelId: String
    let channelName: String
    let imageURL: URL?
    let isVerified: Bool
    let isLive: Bool
    let isOffline: Bool
    let followerCount: Int?
    let isAlreadyAdded: Bool
    let isAdding: Bool
    let isFull: Bool
    /// onAdd 클로저는 Equatable 대상에서 제외 — channelId가 같으면 동작 동일.
    let onAdd: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.channelId      == rhs.channelId      &&
        lhs.channelName    == rhs.channelName    &&
        lhs.isLive         == rhs.isLive         &&
        lhs.isOffline      == rhs.isOffline      &&
        lhs.isAlreadyAdded == rhs.isAlreadyAdded &&
        lhs.isAdding       == rhs.isAdding       &&
        lhs.isFull         == rhs.isFull
    }

    private var canAdd: Bool { !isAlreadyAdded && !isFull && !isAdding && !isOffline }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = imageURL {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { avatarFallback }
                    } else {
                        avatarFallback
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .opacity(isOffline ? 0.45 : 1)

                if isLive {
                    Text("LIVE")
                        .font(DesignTokens.Typography.custom(size: 5.5, weight: .black))
                        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        .padding(.horizontal, DesignTokens.Spacing.xxs).padding(.vertical, 1.5)
                        .background(Capsule().fill(DesignTokens.Colors.live))
                        .offset(y: 3)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(channelName)
                        .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                        .foregroundStyle(isOffline
                                         ? DesignTokens.Colors.textSecondary
                                         : DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.accentBlue)
                    }
                }
                if let fc = followerCount, fc > 0 {
                    Text("팔로워 \(formattedCount(fc))")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(channelId)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Action
            actionView
        }
        .padding(.horizontal, DesignTokens.Spacing.md).padding(.vertical, DesignTokens.Spacing.sm)
        .background(rowBackground)
        .opacity(isOffline ? 0.6 : 1)
        .padding(.horizontal, DesignTokens.Spacing.xs).padding(.vertical, DesignTokens.Spacing.xxs)
        .disabled(!canAdd && !isAlreadyAdded && !isAdding)
    }

    @ViewBuilder
    private var actionView: some View {
        if isAlreadyAdded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(DesignTokens.Typography.custom(size: 16))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("추가됨")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
        } else if isAdding {
            ProgressView().scaleEffect(0.75)
                .tint(DesignTokens.Colors.chzzkGreen)
                .frame(width: 32, height: 32)
        } else if isFull {
            Text("4/4")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        } else if isOffline {
            Text("오프라인")
                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
        } else {
            Button { onAdd() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(DesignTokens.Typography.custom(size: 26))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.35), radius: 5)
            }
            .buttonStyle(.plain)
            .help("\(channelName) 추가")
        }
    }

    // 배경: 단일 shape에 fill + stroke 조건 병합 → overlay 레이어 제거
    @ViewBuilder
    private var rowBackground: some View {
        if isAlreadyAdded {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.white.opacity(0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(DesignTokens.Colors.chzzkGreen.opacity(0.22), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(Color.white.opacity(0.03))
        }
    }

    private var avatarFallback: some View {
        let palette: [Color] = [
            DesignTokens.Colors.accentBlue.opacity(0.7),
            DesignTokens.Colors.accentPurple.opacity(0.7),
            DesignTokens.Colors.accentPink.opacity(0.7),
            DesignTokens.Colors.chzzkGreen.opacity(0.6),
            DesignTokens.Colors.accentOrange.opacity(0.65),
        ]
        return ZStack {
            palette[abs(channelName.hashValue) % palette.count]
            Text(String(channelName.prefix(1)).uppercased())
                .font(DesignTokens.Typography.bodySemibold)
                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        }
    }

    private func formattedCount(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - MLAddChannelPanel (슬라이드 패널 래퍼)
struct MLAddChannelPanel: View {
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var isPresented: Bool
    let onError: (String) -> Void

    var body: some View {
        MLAddChannelSheet(
            manager: manager,
            appState: appState,
            onError: onError,
            onDismiss: { withAnimation(DesignTokens.Animation.snappy) {
                isPresented = false
            }}
        )
        .frame(width: 380)
        .background(DesignTokens.Colors.background)
        .overlay(alignment: .leading) {
            // 좌측 구분선
            Rectangle()
                .fill(DesignTokens.Colors.border.opacity(0.3))
                .frame(width: 1)
        }
    }
}

// MARK: - MLLiveChannelCard (썸네일 카드 뷰)
/// 라이브 채널을 16:9 썸네일 카드로 표시합니다.
@MainActor
struct MLLiveChannelCard: View {
    let item: LiveChannelItem
    let isAlreadyAdded: Bool
    let isAdding: Bool
    let isFull: Bool
    let onAdd: () -> Void

    @State private var isHovered = false

    private var canAdd: Bool { !isAlreadyAdded && !isFull && !isAdding }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 썸네일 영역 ───────────────────────────────
            thumbnailArea
                .aspectRatio(16/9, contentMode: .fit)
                .clipped()
                .overlay(alignment: .topLeading) { liveBadge }
                .overlay(alignment: .topTrailing) { viewerBadge }
                .overlay { if isHovered && canAdd { hoverOverlay } }

            // ── 하단 정보 + 추가 버튼 ────────────────────
            infoBar
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(
                    isAlreadyAdded
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.35)
                        : (isHovered ? DesignTokens.Colors.live.opacity(0.4) : Color.white.opacity(0.06)),
                    lineWidth: 0.5
                )
        )
        .animation(DesignTokens.Animation.micro, value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var thumbnailArea: some View {
        let url = [item.thumbnailUrl, item.channelImageUrl]
            .lazy.compactMap { $0.flatMap(URL.init) }.first
        if let url {
            CachedAsyncImage(url: url) { placeholderGradient }
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [DesignTokens.Colors.surfaceElevated, DesignTokens.Colors.surfaceBase],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(DesignTokens.Typography.custom(size: 7, weight: .black))
            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
            .padding(.horizontal, DesignTokens.Spacing.xxs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.live)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            .padding(DesignTokens.Spacing.xs)
    }

    private var viewerBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "person.fill").font(DesignTokens.Typography.custom(size: 7))
            Text(item.formattedViewerCount)
                .font(DesignTokens.Typography.custom(size: 8, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(DesignTokens.Colors.textOnOverlay)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, 2.5)
        .background(.black.opacity(0.6))
        .clipShape(Capsule())
        .padding(DesignTokens.Spacing.xs)
    }

    private var hoverOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity.animation(DesignTokens.Animation.micro))
    }

    private var infoBar: some View {
        HStack(spacing: 6) {
            // 채널 아바타 (소형)
            CachedAsyncImage(url: URL(string: item.channelImageUrl ?? "")) {
                Circle().fill(DesignTokens.Colors.surfaceElevated)
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())

            // 채널명 + 방송 제목
            VStack(alignment: .leading, spacing: 1) {
                Text(item.channelName)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Text(item.liveTitle)
                    .font(DesignTokens.Typography.custom(size: 8.5))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            // 상태 아이콘
            if isAlreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            } else if isAdding {
                ProgressView().scaleEffect(0.55)
                    .tint(DesignTokens.Colors.chzzkGreen)
            } else if isFull {
                Text("4/4")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 16))
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceBase)
    }
}

// MARK: - MLFollowingEntry (local model)
struct MLFollowingEntry: Identifiable {
    let id: String
    let channelId: String
    let channelName: String
    let imageURL: URL?
    let isLive: Bool
    let isVerified: Bool
}

