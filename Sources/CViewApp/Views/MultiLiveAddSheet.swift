// MARK: - MultiLiveAddSheet.swift
import SwiftUI
import CViewCore
import CViewNetworking

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
    @State private var followingLive: [MLFollowingEntry] = []
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
            Divider().overlay(DesignTokens.Colors.border.opacity(0.15))
            Group {
                switch selectedTab {
                case .following: followingContent
                case .search:    searchContent
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.backgroundDark)
        .onAppear { Task { await loadFollowing() } }
    }

    // MARK: Header
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("채널 추가")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(isFull ? "최대 채널 수에 도달했습니다" : "채널을 선택해 동시에 시청하세요")
                    .font(.system(size: 11))
                    .foregroundStyle(isFull ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                    .animation(.easeInOut(duration: 0.2), value: isFull)
            }
            Spacer()
            Button { dismiss() } label: {
                Text("완료")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                        .overlay(Capsule().stroke(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
    }

    // MARK: Capacity Bar
    private var capacityBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<MultiLiveSessionManager.maxSessions, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < manager.sessions.count
                          ? DesignTokens.Colors.chzzkGreen
                          : Color.white.opacity(0.1))
                    .frame(height: 3)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.sessions.count)
            }
            Text("\(manager.sessions.count)/\(MultiLiveSessionManager.maxSessions)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(isFull ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                .frame(minWidth: 28, alignment: .trailing)
                .animation(.easeInOut(duration: 0.2), value: isFull)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    // MARK: Segment Bar
    private var segmentBar: some View {
        HStack(spacing: 0) {
            segmentBtn("팔로잉 라이브", tab: .following)
            segmentBtn("채널 검색", tab: .search)
        }
        .padding(.horizontal, 18).padding(.bottom, 4)
    }

    @ViewBuilder
    private func segmentBtn(_ label: String, tab: AddTab) -> some View {
        let sel = selectedTab == tab
        Button { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab } } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: sel ? .semibold : .regular))
                    .foregroundStyle(sel ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .padding(.vertical, 2)
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
                                ForEach(followingLive) { entry in
                                    let cid = entry.channelId
                                    MLChannelRowView(
                                        channelId:      cid,
                                        channelName:    entry.channelName,
                                        imageURL:       entry.imageURL,
                                        isVerified:     entry.isVerified,
                                        isLive:         true,
                                        isOffline:      false,
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
                    .padding(.vertical, 4)
                    // 페이지네이션 중 하단 인디케이터
                    if isLoadingFollowing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.65).tint(DesignTokens.Colors.chzzkGreen)
                            Text("더 불러오는 중...")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
                // 새로고침 버튼 (우상단)
                Button { Task { await loadFollowing() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .rotationEffect(.degrees(isLoadingFollowing ? 360 : 0))
                        // .default 종료 애니메이션 → 현재 각도에서 0°로 역회전 버벅임 발생.
                        // .linear(duration: 0) 으로 즉시 정지.
                        .animation(
                            isLoadingFollowing
                                ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                                : .linear(duration: 0),
                            value: isLoadingFollowing
                        )
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.065)))
                }
                .buttonStyle(.plain)
                .disabled(isLoadingFollowing)
                .padding(.top, 6).padding(.trailing, 12)
            }
        }
    }

    private func sectionHeader(dot: Color, title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("\(count)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(DesignTokens.Colors.backgroundDark)
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
                    .padding(.horizontal, 8).padding(.vertical, 6)
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
                .font(.system(size: 13))
                .animation(.easeInOut(duration: 0.15), value: searchQuery.isEmpty)

            TextField("채널명 또는 채널 ID 검색", text: $searchQuery)
                .textFieldStyle(.plain).font(.system(size: 13))
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
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(searchQuery.isEmpty
                            ? Color.white.opacity(0.08)
                            : DesignTokens.Colors.chzzkGreen.opacity(0.35),
                            lineWidth: 1))
        )
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: searchQuery.isEmpty)
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        VStack(spacing: 18) {
            if searchQuery.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.35))
                Text("채널명을 검색하세요")
                    .font(.system(size: 13)).foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                Image(systemName: "exclamationmark.magnifyingglass")
                    .font(.system(size: 36)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.35))
                VStack(spacing: 4) {
                    Text("검색 결과가 없습니다")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text("\"\(searchQuery)\"")
                        .font(.system(size: 11)).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                // 채널 ID 직접 추가
                if !isFull && !manager.sessions.contains(where: { $0.channelId == searchQuery }) {
                    VStack(spacing: 8) {
                        Text("채널 ID로 직접 추가")
                            .font(.system(size: 11))
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
                                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                }
                                Text(trimmed)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                        }
                        .buttonStyle(.plain)
                        .disabled(isAdding)
                    }
                    .padding(.top, 4)
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
            Text(text).font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(_ message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32)).foregroundStyle(.orange.opacity(0.75))
            Text(message)
                .font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Button(action: onRetry) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    Text("다시 시도").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 8)
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
                .font(.system(size: 38)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.55))
            Text("로그인이 필요합니다")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("팔로잉 목록을 보려면 로그인이 필요합니다.\n채널 검색에서 직접 추가할 수 있습니다.")
                .font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Button { withAnimation { selectedTab = .search } } label: {
                Text("채널 검색으로 이동")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().stroke(DesignTokens.Colors.chzzkGreen.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyFollowingView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36)).foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.45))
            Text("팔로잉 채널이 없습니다")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(DesignTokens.Colors.textSecondary)
            Button { withAnimation { selectedTab = .search } } label: {
                Text("채널 검색으로 이동")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().stroke(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data Loading

    /// 팔로잉 전체 목록을 페이지네이션으로 전부 가져옵니다.
    /// API는 page.next.offset 커서 방식을 사용합니다.
    private func loadFollowing() async {
        guard let apiClient = appState.apiClient, appState.isLoggedIn else { return }
        isLoadingFollowing = true
        followingLoadError = nil
        // 새로 불러오는 동안 이전 결과 초기화 (재로드 시 중복 노출 방지)
        followingLive    = []
        followingOffline = []
        defer { isLoadingFollowing = false }

        var live:    [MLFollowingEntry] = []
        var offline: [MLFollowingEntry] = []
        var seenIds: Set<String> = []   // 중복 방지
        let batchSize = 50              // 치지직 API 안정적 최대값
        var currentPage = 0             // 0-indexed 페이지 번호
        let maxPages = 50               // 안전 상한 (총 2500채널)

        do {
            while currentPage < maxPages {
                let result = try await apiClient.following(size: batchSize, page: currentPage)
                let items = result.followingList ?? []

                for item in items {
                    guard let ch    = item.channel,
                          let cid   = ch.channelId,
                          let cname = ch.channelName,
                          !seenIds.contains(cid)
                    else { continue }
                    seenIds.insert(cid)
                    let isLive = item.streamer?.isActuallyLive ?? false
                    let entry = MLFollowingEntry(
                        id:          cid,
                        channelId:   cid,
                        channelName: cname,
                        imageURL:    ch.channelImageUrl.flatMap { URL(string: $0) },
                        isLive:      isLive,
                        isVerified:  ch.verifiedMark ?? false
                    )
                    if entry.isLive { live.append(entry) } else { offline.append(entry) }
                }

                // 중간 결과 즉시 반영 (사용자가 빠르게 확인 가능)
                followingLive    = live
                followingOffline = offline

                // totalCount가 있으면 이를 우선 종료 조건으로 사용
                if let total = result.totalCount, seenIds.count >= total { break }

                // 마지막 페이지 판단: 응답 항목 수가 batchSize 미만이면 끝
                if items.count < batchSize { break }

                currentPage += 1
            }
        } catch {
            // 이미 일부 로드된 항목이 있으면 에러 메시지는 표시하지 않음
            if live.isEmpty && offline.isEmpty {
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
        guard let session = manager.addSession(channelId: trimmed) else {
            onError("이미 추가된 채널이거나 최대 개수(4)에 도달했습니다."); return
        }
        guard let apiClient = appState.apiClient else {
            onError("API 클라이언트가 초기화되지 않았습니다."); return
        }
        isAddingChannelIds.insert(trimmed)
        defer { isAddingChannelIds.remove(trimmed) }
        // addSession() 이후 sessions.count = 방금 추가된 세션 포함 총 수
        await session.start(using: apiClient, appState: appState, paneCount: manager.sessions.count)
        if isFull { dismiss() }
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
                        .font(.system(size: 5.5, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1.5)
                        .background(Capsule().fill(DesignTokens.Colors.live))
                        .offset(y: 3)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(channelName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isOffline
                                         ? DesignTokens.Colors.textSecondary
                                         : DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.Colors.accentBlue)
                    }
                }
                if let fc = followerCount, fc > 0 {
                    Text("팔로워 \(formattedCount(fc))")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(channelId)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Action
            actionView
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(rowBackground)
        .opacity(isOffline ? 0.6 : 1)
        .padding(.horizontal, 8).padding(.vertical, 1)
        .disabled(!canAdd && !isAlreadyAdded && !isAdding)
    }

    @ViewBuilder
    private var actionView: some View {
        if isAlreadyAdded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("추가됨")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
        } else if isAdding {
            ProgressView().scaleEffect(0.75)
                .tint(DesignTokens.Colors.chzzkGreen)
                .frame(width: 32, height: 32)
        } else if isFull {
            Text("4/4")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        } else if isOffline {
            Text("오프라인")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
        } else {
            Button { onAdd() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
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
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignTokens.Colors.chzzkGreen.opacity(0.22), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03))
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
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
            onDismiss: { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isPresented = false
            }}
        )
        .frame(width: 340)
        .background(DesignTokens.Colors.backgroundDark)
        .overlay(alignment: .leading) {
            // 좌측 구분선
            Rectangle()
                .fill(DesignTokens.Colors.border.opacity(0.25))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, x: -6, y: 0)
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

