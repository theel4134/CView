// MARK: - PopularClipsView.swift
// CViewApp - 클립 메뉴 (전체 인기클립 + 채널별 클립)
// 2026-04-29 리팩터: 상태를 ClipBrowserViewModel로 분리, 채널 입력은 ID/URL 모두 허용.

import SwiftUI
import AppKit
import CViewCore
import CViewNetworking
import CViewUI

// MARK: - JSON Coders (Phase5 — ClipInfo persistence)

extension JSONEncoder {
    /// ClipInfo 등 클립 모델 영구 저장용 — ISO8601 date.
    static let cv_clip: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let cv_clip: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Public Enums (View와 ViewModel 공유)

/// 클립 메뉴 namespace.
enum ClipBrowser {

    enum ClipTab: String, CaseIterable, Identifiable {
        case trending = "전체 인기클립"
        case channel = "채널별 클립"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .trending: "flame.fill"
            case .channel: "person.text.rectangle"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case popular = "인기순"
        case recent = "최신순"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .popular: "flame"
            case .recent: "clock"
            }
        }
    }

    enum TrendingFilter: String, CaseIterable, Identifiable {
        case today = "오늘"
        case week = "이번 주"
        case month = "이번 달"

        var id: String { rawValue }
        var apiValue: String {
            switch self {
            case .today: "WITHIN_1_DAY"
            case .week: "WITHIN_7_DAYS"
            case .month: "WITHIN_30_DAYS"
            }
        }
    }

    enum TrendingOrder: String, CaseIterable, Identifiable {
        case popular = "인기순"
        case recommend = "추천순"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .popular: "flame"
            case .recommend: "sparkles"
            }
        }
        var apiValue: String {
            switch self {
            case .popular: "POPULAR"
            case .recommend: "RECOMMEND"
            }
        }
    }

    enum ViewMode: String, CaseIterable {
        case grid
        case list
        var icon: String {
            switch self {
            case .grid: "square.grid.2x2"
            case .list: "list.bullet"
            }
        }
    }
}

// MARK: - Channel Resolver

/// 사용자가 입력한 문자열에서 채널 식별자를 뽑아낸다.
/// - 채널 URL(`https://chzzk.naver.com/{channelId}` 또는 `.../live` 등) → channelId 추출
/// - channelId 형태(영문/숫자 16~64자) → 그대로
/// - 그 외 → nil
enum ChannelResolver {
    /// 입력값을 trimming하고 채널 ID를 추출한다.
    static func resolveChannelId(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let id = parseChannelIdFromURL(trimmed) {
            return id
        }
        if looksLikeChannelId(trimmed) {
            return trimmed
        }
        return nil
    }

    /// URL에서 channelId를 추출한다. (chzzk.naver.com path 첫 segment)
    static func parseChannelIdFromURL(_ raw: String) -> String? {
        guard raw.contains("/") || raw.lowercased().hasPrefix("http") else { return nil }

        let normalized: String
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            normalized = raw
        } else {
            normalized = "https://" + raw
        }

        guard let url = URL(string: normalized),
              let host = url.host?.lowercased(),
              host.contains("chzzk.naver.com") else {
            return nil
        }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = parts.first else { return nil }
        if first == "clips" || first == "live" || first == "video" { return nil }
        return looksLikeChannelId(first) ? first : nil
    }

    /// 채널 ID 후보 형태인지 검사. 치지직 channelId는 hex 32자리가 일반적.
    static func looksLikeChannelId(_ s: String) -> Bool {
        guard s.count >= 16 && s.count <= 64 else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

// MARK: - ClipBrowserViewModel

/// 클립 메뉴 상태/요청 관리. View에서 분리하여 테스트 가능하게 한다.
@Observable
@MainActor
final class ClipBrowserViewModel {
    // MARK: Tabs/Modes
    var selectedTab: ClipBrowser.ClipTab = .trending
    var viewMode: ClipBrowser.ViewMode = .grid

    // MARK: Trending
    var trendingClips: [ClipInfo] = []
    var trendingIsLoading = false
    var trendingError: String?
    var trendingFilter: ClipBrowser.TrendingFilter = .week
    var trendingOrder: ClipBrowser.TrendingOrder = .popular

    // MARK: Channel
    var channelInput: String = ""
    /// resolveChannelId로 정규화된 channelId. 입력 검증 실패 시 nil.
    var resolvedChannelId: String?
    var channelClips: [ClipInfo] = []
    var channelIsLoading = false
    var channelError: String?
    var channelPage = 0
    var channelTotalCount: Int?
    var channelHasMore = true
    var channelSortOrder: ClipBrowser.SortOrder = .popular

    // MARK: Channel Suggestions (채널명 검색)
    /// 에 채널명 키워드로 검색한 채널 후보 목록.
    var channelSuggestions: [CViewCore.ChannelInfo] = []
    var isSearchingChannels = false
    /// 판챍 차단용 token — 이전 검색 결과가 최신 keyword를 덮어쓰는 것 방지.
    @ObservationIgnored private var suggestionToken: UInt64 = 0

    // MARK: Selection
    /// 클립 sheet 재생 트리거. set 되면 ClipPlayerView가 열린다.
    var selectedClip: ClipInfo?
    /// inspector preview 대상. 카드 click 시 우측 inspector에서 보여준다.
    var previewClip: ClipInfo?

    // MARK: Watch Later / Queue
    /// 영구 보관 — 나중에 보기 (UserDefaults 백업).
    var watchLaterUIDs: Set<String> = []
    /// 큐 — 다음 클립 재생용. [2026-04-30 Phase5] persist.
    var queueClips: [ClipInfo] = []
    /// [2026-04-30 Phase5] 저장된 클립 snapshot — 앱 재시작 후 메모리 목록에 없어도 복원.
    /// key: clipUID
    var savedClipSnapshots: [String: ClipInfo] = [:]

    @ObservationIgnored private let watchLaterDefaultsKey = "ClipBrowser.watchLaterUIDs"
    @ObservationIgnored private let savedSnapshotsDefaultsKey = "ClipBrowser.savedClipSnapshots.v1"
    @ObservationIgnored private let queueDefaultsKey = "ClipBrowser.queueClips.v1"
    @ObservationIgnored private let recentChannelsDefaultsKey = "ClipBrowser.recentChannels.v1"

    /// [2026-04-30 Phase2] 최근 본 채널 — 채널 탭 빈 화면 빠른 접근.
    /// 최신순, 최대 8개 유지.
    var recentChannels: [ChannelInfo] = []

    // MARK: Display Pagination (Phase3 — 한 번에 렌더링되는 클립 수 제한)
    /// 한 페이지에 보여줄 클립 수. 너무 크면 LazyVGrid가 누적 렌더링 비용 증가.
    let displayPageSize: Int = 24
    /// 현재 채널 클립 디스플레이 페이지 (0-based).
    var channelDisplayPage: Int = 0
    /// 현재 인기 클립 디스플레이 페이지 (0-based).
    var trendingDisplayPage: Int = 0

    // MARK: Internals
    private let pageSize = 20
    /// 비동기 요청 중첩 시 stale result 방지를 위한 토큰.
    private var trendingRequestToken: UInt64 = 0
    private var channelRequestToken: UInt64 = 0

    // MARK: API client (외부 주입)
    @ObservationIgnored weak var apiClient: ChzzkAPIClient?

    // MARK: - Trending

    func loadTrendingClips() async {
        guard let client = apiClient else {
            trendingError = "API 클라이언트가 초기화되지 않았습니다"
            return
        }
        trendingRequestToken &+= 1
        let token = trendingRequestToken
        trendingIsLoading = true
        trendingError = nil

        do {
            let clips = try await client.homePopularClips(
                filterType: trendingFilter.apiValue,
                orderType: trendingOrder.apiValue
            )
            guard token == trendingRequestToken else { return }
            trendingClips = clips
            trendingDisplayPage = 0
        } catch {
            guard token == trendingRequestToken else { return }
            trendingError = "인기 클립 로드 실패: \(error.localizedDescription)"
        }
        if token == trendingRequestToken {
            trendingIsLoading = false
        }
    }

    // MARK: - Channel

    /// 사용자가 입력 필드에서 submit 했을 때 호출. URL/ID 모두 처리.
    func submitChannelInput() {
        guard let id = ChannelResolver.resolveChannelId(from: channelInput) else {
            channelError = "채널 ID 또는 채널 URL 형식이 올바르지 않습니다"
            channelClips = []
            resolvedChannelId = nil
            return
        }
        resolvedChannelId = id
        loadChannelClips(reset: true)
    }

    func loadChannelClips(reset: Bool) {
        guard let channelId = resolvedChannelId, !channelId.isEmpty else { return }

        if reset {
            channelPage = 0
            channelHasMore = true
            channelClips = []
            channelDisplayPage = 0
        }

        channelRequestToken &+= 1
        let token = channelRequestToken
        let pageToFetch = channelPage

        Task { @MainActor in
            channelIsLoading = true
            channelError = nil

            guard let client = apiClient else {
                if token == channelRequestToken {
                    channelError = "API 클라이언트가 초기화되지 않았습니다"
                    channelIsLoading = false
                }
                return
            }

            do {
                let result = try await client.clipList(
                    channelId: channelId,
                    page: pageToFetch,
                    size: pageSize
                )
                guard token == channelRequestToken,
                      channelId == resolvedChannelId else { return }

                if reset {
                    channelClips = result.data
                } else {
                    // [2026-04-30 Phase3] 중복 clipUID 제거 후 append — API가 페이지 경계에서 같은 클립을 재반환하는 경우 방지.
                    let existing = Set(channelClips.map { $0.clipUID })
                    let unique = result.data.filter { !existing.contains($0.clipUID) }
                    channelClips.append(contentsOf: unique)
                }
                channelTotalCount = result.totalCount
                channelHasMore = result.data.count >= pageSize

                if channelSortOrder == .popular {
                    channelClips.sort { $0.readCount > $1.readCount }
                }

                // [2026-04-30 Phase2] 최근 채널 기록 — 첫 클립의 channel 정보 사용
                if reset, let ch = result.data.first?.channel {
                    addRecentChannel(ch)
                }
            } catch {
                guard token == channelRequestToken else { return }
                channelError = "클립 로드 실패: \(error.localizedDescription)"
            }
            if token == channelRequestToken {
                channelIsLoading = false
            }
        }
    }

    func loadMoreChannelClipsIfNeeded() {
        guard channelHasMore, !channelIsLoading else { return }
        channelPage += 1
        loadChannelClips(reset: false)
    }

    // MARK: - Display Pagination Helpers (Phase3)

    /// 현재 디스플레이 페이지에 해당하는 채널 클립 슬라이스.
    var displayedChannelClips: ArraySlice<ClipInfo> {
        let start = channelDisplayPage * displayPageSize
        guard start < channelClips.count else { return [] }
        let end = min(start + displayPageSize, channelClips.count)
        return channelClips[start..<end]
    }

    /// 채널 클립 디스플레이 총 페이지 수 (현재까지 fetch된 + 추가 fetch 가능량 추정).
    var channelTotalDisplayPages: Int {
        if let total = channelTotalCount, total > 0 {
            return Int(ceil(Double(total) / Double(displayPageSize)))
        }
        return max(1, Int(ceil(Double(channelClips.count) / Double(displayPageSize))))
    }

    /// 채널 페이지 이동 — 데이터가 부족하면 추가 fetch 후 자동 이동.
    func goToChannelDisplayPage(_ page: Int) {
        guard page >= 0, page < channelTotalDisplayPages else { return }
        let needed = (page + 1) * displayPageSize
        if channelClips.count >= needed || !channelHasMore {
            channelDisplayPage = page
        } else {
            // prefetch 후 적용 — 로드 완료 시 onChange로 페이지 적용은 어려우니 즉시 적용 + 백그라운드 fetch
            channelDisplayPage = page
            loadMoreChannelClipsIfNeeded()
        }
    }

    /// 현재 디스플레이 페이지에 해당하는 인기 클립 슬라이스.
    var displayedTrendingClips: ArraySlice<ClipInfo> {
        let start = trendingDisplayPage * displayPageSize
        guard start < trendingClips.count else { return [] }
        let end = min(start + displayPageSize, trendingClips.count)
        return trendingClips[start..<end]
    }

    var trendingTotalDisplayPages: Int {
        max(1, Int(ceil(Double(trendingClips.count) / Double(displayPageSize))))
    }

    func goToTrendingDisplayPage(_ page: Int) {
        guard page >= 0, page < trendingTotalDisplayPages else { return }
        trendingDisplayPage = page
    }

    /// 채널 선택 해제 — 빈 화면(가이드)으로 복귀.
    func clearChannelSelection() {
        resolvedChannelId = nil
        channelInput = ""
        channelClips = []
        channelTotalCount = nil
        channelDisplayPage = 0
        channelError = nil
    }

    // MARK: - Clip Actions

    /// 카드 click 진입점.
    /// 넓은 화면(인스펙터 가능) → previewClip 갱신, 우측 인스펙터 표시.
    /// 좁은 화면 → selectedClip sheet 즉시 재생.
    /// [2026-04-30 Phase1 정밀 재설계: 인스펙터 활성화]
    func handleClipTap(_ clip: ClipInfo, inspectorAvailable: Bool = false) {
        if inspectorAvailable {
            previewClip = clip
        } else {
            selectedClip = clip
        }
    }

    /// 클립 sheet 재생 시작 (인스펙터의 재생 버튼 / 직접 재생 경로).
    func playClip(_ clip: ClipInfo) {
        selectedClip = clip
    }

    /// 치지직 클립 page를 외부 브라우저에서 연다.
    func openOriginalClip(_ clip: ClipInfo) {
        guard let url = URL(string: "https://chzzk.naver.com/clips/\(clip.clipUID)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 클립 공유 링크를 클립보드에 복사.
    func copyClipLink(_ clip: ClipInfo) {
        let link = "https://chzzk.naver.com/clips/\(clip.clipUID)"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(link, forType: .string)
    }

    /// 채널 ID를 채널별 클립 탭 입력으로 채우고 channel 탭으로 전환한다.
    func showChannelClips(_ channelId: String) {
        channelInput = channelId
        resolvedChannelId = channelId
        selectedTab = .channel
        loadChannelClips(reset: true)
    }

    // MARK: - Channel Suggestion Search

    /// 채널명 키워드를 debounce 후 검색. URL/ID일 때는 호출하지 않는다.
    func updateChannelSuggestions(for keyword: String) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        // 이미 ID/URL로 매칭되면 검색 필요 없음
        if trimmed.isEmpty || ChannelResolver.resolveChannelId(from: trimmed) != nil {
            channelSuggestions = []
            isSearchingChannels = false
            return
        }
        // 한글의 경우 1글자에서도 검색 의미 있음. 영문은 2글자 이상으로 제한.
        if trimmed.allSatisfy({ $0.isASCII }) && trimmed.count < 2 {
            channelSuggestions = []
            isSearchingChannels = false
            return
        }

        suggestionToken &+= 1
        let token = suggestionToken

        // Debounce 250ms
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard token == suggestionToken else { return }

        guard let client = apiClient else { return }
        isSearchingChannels = true
        defer {
            if token == suggestionToken { isSearchingChannels = false }
        }

        do {
            let result = try await client.searchChannels(keyword: trimmed, offset: 0, size: 8)
            guard token == suggestionToken else { return }
            channelSuggestions = result.data
        } catch {
            guard token == suggestionToken else { return }
            channelSuggestions = []
        }
    }

    /// 검색 후보 또는 팔로잉에서 선택된 채널로 채널별 클립을 로드.
    func selectChannelSuggestion(channelId: String, channelName: String) {
        channelInput = channelName
        resolvedChannelId = channelId
        channelSuggestions = []
        loadChannelClips(reset: true)
    }

    // MARK: - Watch Later

    /// UserDefaults에서 watch later 목록 + snapshot + queue 로드. View .onAppear에서 호출.
    /// [2026-04-30 Phase5] snapshot/queue 영구 복원 추가.
    func loadWatchLaterFromDefaults() {
        if let arr = UserDefaults.standard.array(forKey: watchLaterDefaultsKey) as? [String] {
            watchLaterUIDs = Set(arr)
        }
        // Snapshots
        if let data = UserDefaults.standard.data(forKey: savedSnapshotsDefaultsKey),
           let decoded = try? JSONDecoder.cv_clip.decode([String: ClipInfo].self, from: data) {
            savedClipSnapshots = decoded
        }
        // Queue
        if let data = UserDefaults.standard.data(forKey: queueDefaultsKey),
           let decoded = try? JSONDecoder.cv_clip.decode([ClipInfo].self, from: data) {
            queueClips = decoded
        }
        // Recent channels
        if let data = UserDefaults.standard.data(forKey: recentChannelsDefaultsKey),
           let decoded = try? JSONDecoder.cv_clip.decode([ChannelInfo].self, from: data) {
            recentChannels = decoded
        }
    }

    private func persistWatchLater() {
        UserDefaults.standard.set(Array(watchLaterUIDs), forKey: watchLaterDefaultsKey)
    }

    private func persistSnapshots() {
        if let data = try? JSONEncoder.cv_clip.encode(savedClipSnapshots) {
            UserDefaults.standard.set(data, forKey: savedSnapshotsDefaultsKey)
        }
    }

    private func persistQueue() {
        if let data = try? JSONEncoder.cv_clip.encode(queueClips) {
            UserDefaults.standard.set(data, forKey: queueDefaultsKey)
        }
    }

    // MARK: - Recent Channels (Phase2)

    /// 최근 채널 추가 — 중복 제거 후 맨 앞에 삽입, 최대 8개 유지.
    func addRecentChannel(_ channel: ChannelInfo) {
        recentChannels.removeAll { $0.channelId == channel.channelId }
        recentChannels.insert(channel, at: 0)
        if recentChannels.count > 8 {
            recentChannels = Array(recentChannels.prefix(8))
        }
        persistRecentChannels()
    }

    func clearRecentChannels() {
        recentChannels.removeAll()
        persistRecentChannels()
    }

    private func persistRecentChannels() {
        if let data = try? JSONEncoder.cv_clip.encode(recentChannels) {
            UserDefaults.standard.set(data, forKey: recentChannelsDefaultsKey)
        }
    }

    func isWatchLater(_ clip: ClipInfo) -> Bool {
        watchLaterUIDs.contains(clip.clipUID)
    }

    func toggleWatchLater(_ clip: ClipInfo) {
        if watchLaterUIDs.contains(clip.clipUID) {
            watchLaterUIDs.remove(clip.clipUID)
            savedClipSnapshots.removeValue(forKey: clip.clipUID)
        } else {
            watchLaterUIDs.insert(clip.clipUID)
            savedClipSnapshots[clip.clipUID] = clip
        }
        persistWatchLater()
        persistSnapshots()
    }

    // MARK: - Queue

    func isInQueue(_ clip: ClipInfo) -> Bool {
        queueClips.contains(where: { $0.clipUID == clip.clipUID })
    }

    func addToQueue(_ clip: ClipInfo) {
        guard !isInQueue(clip) else { return }
        queueClips.append(clip)
        persistQueue()
    }

    func removeFromQueue(_ clip: ClipInfo) {
        queueClips.removeAll { $0.clipUID == clip.clipUID }
        persistQueue()
    }

    func clearQueue() {
        queueClips.removeAll()
        persistQueue()
    }

    /// 큐의 다음 클립을 꺼내 재생 (현재 클립 다음 항목).
    func playNextInQueue(after current: ClipInfo?) -> ClipInfo? {
        guard !queueClips.isEmpty else { return nil }
        if let current,
           let idx = queueClips.firstIndex(where: { $0.clipUID == current.clipUID }),
           idx + 1 < queueClips.count {
            return queueClips[idx + 1]
        }
        return queueClips.first
    }
}

// MARK: - PopularClipsView

/// 인기 클립 브라우저 — 치지직 전체 인기클립 + 채널별 클립 탐색, 정렬, 재생
struct PopularClipsView: View {

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @State private var vm = ClipBrowserViewModel()
    @Namespace private var tabNS
    @State private var isSearchFocused = false
    @State private var showSuggestions = false
    @State private var showFollowingPicker = false
    @State private var showQueuePopover = false
    @State private var showWatchLaterPopover = false

    /// inspector 표시에 필요한 최소 너비. 이 미만이면 카드 click이 곧바로 sheet로 진입한다.
    /// 문서 §4 반응형 폭 규칙: 1100pt 이상 우측 고정 인스펙터.
    private let inspectorMinWidth: CGFloat = 1100
    /// inspector panel 폭 (문서 §4 — 1100-1439pt 320pt).
    private let inspectorWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            // [2026-04-30] toolbar 하단 액센트 라인 — 그라디언트 1px
            LinearGradient(
                colors: [
                    DesignTokens.Colors.accentPink.opacity(0.35),
                    DesignTokens.Colors.chzzkGreen.opacity(0.30),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            // [2026-04-30 Phase1] GeometryReader 기반 폭 분기 — 우측 인스펙터 활성화
            GeometryReader { proxy in
                let inspectorAvailable = proxy.size.width >= inspectorMinWidth

                HStack(spacing: 0) {
                    Group {
                        switch vm.selectedTab {
                        case .trending:
                            trendingContent(inspectorAvailable: inspectorAvailable)
                                .transition(.opacity)
                        case .channel:
                            channelContent(inspectorAvailable: inspectorAvailable)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if inspectorAvailable, let preview = vm.previewClip {
                        Divider()
                        inspectorPanel(for: preview)
                            .frame(width: inspectorWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Animation.snappy, value: vm.previewClip?.clipUID)
                .animation(DesignTokens.Animation.snappy, value: inspectorAvailable)
                // 폭이 좁아졌을 때 preview 자동 정리
                .onChange(of: inspectorAvailable) { _, newValue in
                    if !newValue { vm.previewClip = nil }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // [2026-04-30 Phase4] Filmstrip Dock — 큐/저장 상시 노출 (큐가 있을 때만)
            if !vm.queueClips.isEmpty || !vm.watchLaterUIDs.isEmpty {
                Divider()
                ClipFilmstripDock(
                    queueClips: vm.queueClips,
                    watchLaterClips: collectWatchLaterClips(),
                    onPlay: { vm.playClip($0) },
                    onPreview: { vm.previewClip = $0 },
                    onRemoveFromQueue: { vm.removeFromQueue($0) },
                    onClearQueue: { vm.clearQueue() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .animation(DesignTokens.Animation.snappy, value: vm.queueClips.count)
        .animation(DesignTokens.Animation.snappy, value: vm.watchLaterUIDs.count)
        .sheet(item: Binding(
            get: { vm.selectedClip },
            set: { vm.selectedClip = $0 }
        )) { clip in
            ClipPlayerView(clipInfo: clip)
                .frame(minWidth: 640, minHeight: 400)
        }
        .task {
            vm.apiClient = appState.apiClient
            vm.loadWatchLaterFromDefaults()
            if vm.trendingClips.isEmpty {
                await vm.loadTrendingClips()
            }
        }
    }

    // MARK: - Inspector Panel (Phase1 활성화)

    @ViewBuilder
    private func inspectorPanel(for clip: ClipInfo) -> some View {
        ClipPreviewInspector(
            clip: clip,
            onPlay: { vm.playClip(clip) },
            onOpenChannel: {
                if let channelId = clip.channel?.channelId {
                    vm.showChannelClips(channelId)
                }
            },
            onShowChannelClips: {
                if let channelId = clip.channel?.channelId {
                    vm.showChannelClips(channelId)
                }
            },
            onOpenOriginal: { vm.openOriginalClip(clip) },
            onCopyLink: { vm.copyClipLink(clip) },
            onClose: { vm.previewClip = nil },
            isWatchLater: vm.isWatchLater(clip),
            onToggleWatchLater: { vm.toggleWatchLater(clip) },
            isInQueue: vm.isInQueue(clip),
            onToggleQueue: {
                if vm.isInQueue(clip) {
                    vm.removeFromQueue(clip)
                } else {
                    vm.addToQueue(clip)
                }
            }
        )
        .background(DesignTokens.Colors.surfaceBase)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // ── Zone 1: 아이덴티티
                identityBlock

                Spacer(minLength: DesignTokens.Spacing.md)

                // ── Zone 2: 컨텍스트 컨트롤 (탭별 필터)
                if vm.selectedTab == .trending {
                    trendingControls
                } else {
                    channelControls
                }

                // ── Zone 3: 도구 (뷰모드 토글 + 큐 + 북마크) — 한 카드 안에 묶음
                HStack(spacing: 6) {
                    viewModeSegment

                    // 미세 디바이더
                    Rectangle()
                        .fill(DesignTokens.Glass.borderColorLight.opacity(0.45))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)

                    queueButton
                    watchLaterButton
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs + 2)

            tabBar
        }
        .contentBackground()
    }

    /// [2026-04-30 Pass2] 아이덴티티 — 그라디언트 아이콘 + 타이틀 + 동적 서브레이블
    private var identityBlock: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.accentPink.opacity(0.26),
                                DesignTokens.Colors.accentOrange.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(DesignTokens.Colors.accentPink.opacity(0.32), lineWidth: 0.7)
                    }
                    .shadow(color: DesignTokens.Colors.accentPink.opacity(0.18), radius: 6, y: 2)
                Image(systemName: "film.stack.fill")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.accentPink)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("클립")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(vm.selectedTab == .trending
                     ? "인기 클립 · \(vm.trendingFilter.rawValue) · \(vm.trendingOrder.rawValue)"
                     : "채널별 클립")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// [2026-04-30 Pass2] 뷰모드 segmented capsule — 격리된 컨테이너
    private var viewModeSegment: some View {
        HStack(spacing: 1) {
            ForEach(ClipBrowser.ViewMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.indicator) { vm.viewMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(vm.viewMode == mode
                                      ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                                      : .clear)
                        )
                        .foregroundStyle(vm.viewMode == mode
                                         ? DesignTokens.Colors.chzzkGreen
                                         : DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help(mode == .grid ? "그리드 보기" : "리스트 보기")
            }
        }
        .padding(2)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private var trendingControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 2) {
                ForEach(ClipBrowser.TrendingFilter.allCases) { filter in
                    Button {
                        vm.trendingFilter = filter
                        Task { await vm.loadTrendingClips() }
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignTokens.Typography.captionMedium)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(vm.trendingFilter == filter ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                            )
                            .foregroundStyle(vm.trendingFilter == filter ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }

            HStack(spacing: 2) {
                ForEach(ClipBrowser.TrendingOrder.allCases) { order in
                    Button {
                        vm.trendingOrder = order
                        Task { await vm.loadTrendingClips() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: order.icon).font(DesignTokens.Typography.micro)
                            Text(order.rawValue).font(DesignTokens.Typography.captionMedium)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(vm.trendingOrder == order ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                        )
                        .foregroundStyle(vm.trendingOrder == order ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
        }
    }

    private var channelControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(isSearchFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                TextField("채널명, ID, 또는 URL", text: $vm.channelInput)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.caption)
                    .frame(width: 200)
                    .onSubmit { vm.submitChannelInput() }
                    .task(id: vm.channelInput) {
                        await vm.updateChannelSuggestions(for: vm.channelInput)
                    }
                    .onChange(of: vm.channelSuggestions.isEmpty) { _, isEmpty in
                        showSuggestions = !isEmpty
                    }
                if !vm.channelInput.isEmpty {
                    Button { vm.submitChannelInput() } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(isSearchFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Glass.borderColor, lineWidth: 1)
            )
            .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                channelSuggestionsList
            }

            // 팔로잉 채널 picker
            Button {
                showFollowingPicker = true
            } label: {
                Image(systemName: "person.2.fill")
                    .font(DesignTokens.Typography.captionSemibold)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
            }
            .buttonStyle(.plain)
            .help("팔로잉 채널에서 선택")
            .popover(isPresented: $showFollowingPicker, arrowEdge: .bottom) {
                followingChannelPicker
            }

            // [2026-04-30 Phase2] 선택된 채널 칩 — resolvedChannelId 가 있을 때만 표시
            if vm.resolvedChannelId != nil {
                selectedChannelChip
            }

            HStack(spacing: 2) {
                ForEach(ClipBrowser.SortOrder.allCases) { order in
                    Button {
                        vm.channelSortOrder = order
                        vm.loadChannelClips(reset: true)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: order.icon).font(DesignTokens.Typography.micro)
                            Text(order.rawValue).font(DesignTokens.Typography.captionMedium)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(vm.channelSortOrder == order ? DesignTokens.Colors.chzzkGreen.opacity(0.15) : .clear)
                        )
                        .foregroundStyle(vm.channelSortOrder == order ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5) }
        }
    }

    /// [2026-04-30 Phase2] 선택된 채널 칩 — 채널 이미지 + 이름 + ID 일부 + 변경 버튼.
    /// channelClips 의 첫 항목에서 채널 메타를 가져온다 (없으면 ID 만 표시).
    private var selectedChannelChip: some View {
        let channelInfo = vm.channelClips.first?.channel
        let channelName = channelInfo?.channelName ?? vm.channelInput
        let channelId = vm.resolvedChannelId ?? ""
        let idShort = channelId.count > 8 ? String(channelId.prefix(8)) + "…" : channelId

        return HStack(spacing: 6) {
            if let url = channelInfo?.channelImageURL {
                CachedAsyncImage(url: url) {
                    Circle().fill(DesignTokens.Colors.surfaceBase)
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.4), lineWidth: 0.7) }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(channelName.isEmpty ? "채널" : channelName)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                if !idShort.isEmpty {
                    Text(idShort)
                        .font(DesignTokens.Typography.custom(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .frame(maxWidth: 120, alignment: .leading)

            Button {
                vm.clearChannelSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .customCursor(.pointingHand)
            .help("선택 해제")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(DesignTokens.Colors.chzzkGreen.opacity(0.10), in: Capsule())
        .overlay { Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 0.6) }
    }
    private var channelSuggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("채널 검색 결과")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                if vm.isSearchingChannels {
                    ProgressView().controlSize(.mini).tint(DesignTokens.Colors.chzzkGreen)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            Divider()

            if vm.channelSuggestions.isEmpty {
                Text("일치하는 채널 없음")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(DesignTokens.Spacing.md)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.channelSuggestions, id: \.channelId) { ch in
                            channelSuggestionRow(
                                channelId: ch.channelId,
                                channelName: ch.channelName,
                                imageURL: ch.channelImageURL,
                                isLive: ch.openLive,
                                onSelect: { showSuggestions = false }
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 260)
    }

    /// 팔로잉 채널 picker (popover)
    private var followingChannelPicker: some View {
        let channels = appState.homeViewModel?.followingChannels ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text("팔로잉 채널")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
            Divider()

            if channels.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("팔로잉 중인 채널이 없습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.Spacing.md)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(channels, id: \.id) { ch in
                            channelSuggestionRow(
                                channelId: ch.channelId,
                                channelName: ch.channelName,
                                imageURL: ch.channelImageUrl.flatMap { URL(string: $0) },
                                isLive: ch.isLive,
                                onSelect: { showFollowingPicker = false }
                            )
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 240)
    }

    /// 공용 channel row — ChannelSuggestionsList와 FollowingChannelPicker 공용
    private func channelSuggestionRow(
        channelId: String,
        channelName: String,
        imageURL: URL?,
        isLive: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button {
            vm.selectChannelSuggestion(channelId: channelId, channelName: channelName)
            onSelect()
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if let url = imageURL {
                    CachedAsyncImage(url: url) {
                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                } else {
                    Circle().fill(DesignTokens.Colors.surfaceElevated).frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(channelName)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if isLive {
                        HStack(spacing: 3) {
                            Circle().fill(DesignTokens.Colors.accentPink).frame(width: 5, height: 5)
                            Text("LIVE").font(DesignTokens.Typography.micro)
                        }
                        .foregroundStyle(DesignTokens.Colors.accentPink)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .customCursor(.pointingHand)
    }

    // MARK: - Queue / Watch Later buttons

    private var queueButton: some View {
        Button {
            showQueuePopover.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(DesignTokens.Typography.captionSemibold)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(vm.queueClips.isEmpty ? Color.clear : DesignTokens.Colors.accentPink.opacity(0.15))
                    )
                    .foregroundStyle(vm.queueClips.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.accentPink)
                if !vm.queueClips.isEmpty {
                    Text("\(vm.queueClips.count)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignTokens.Colors.accentPink, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("재생 큐")
        .popover(isPresented: $showQueuePopover, arrowEdge: .bottom) {
            queuePopoverContent
                .frame(width: 320, height: 360)
        }
    }

    private var watchLaterButton: some View {
        Button {
            showWatchLaterPopover.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: vm.watchLaterUIDs.isEmpty ? "bookmark" : "bookmark.fill")
                    .font(DesignTokens.Typography.captionSemibold)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(vm.watchLaterUIDs.isEmpty ? Color.clear : DesignTokens.Colors.accentOrange.opacity(0.15))
                    )
                    .foregroundStyle(vm.watchLaterUIDs.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.accentOrange)
                if !vm.watchLaterUIDs.isEmpty {
                    Text("\(vm.watchLaterUIDs.count)")
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignTokens.Colors.accentOrange, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("나중에 보기")
        .popover(isPresented: $showWatchLaterPopover, arrowEdge: .bottom) {
            watchLaterPopoverContent
                .frame(width: 320, height: 360)
        }
    }

    private var queuePopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("재생 큐")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                if !vm.queueClips.isEmpty {
                    Button("모두 비우기") { vm.clearQueue() }
                        .font(DesignTokens.Typography.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .padding(DesignTokens.Spacing.md)
            Divider()
            if vm.queueClips.isEmpty {
                emptyPopoverState(icon: "tray", message: "큐에 추가된 클립이 없어요")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.queueClips, id: \.clipUID) { clip in
                            popoverClipRow(
                                clip: clip,
                                trailingIcon: "minus.circle",
                                onSelect: {
                                    showQueuePopover = false
                                    vm.playClip(clip)
                                },
                                onTrailing: { vm.removeFromQueue(clip) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .background(DesignTokens.Colors.surfaceBase)
    }

    private var watchLaterPopoverContent: some View {
        let clips = collectWatchLaterClips()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("나중에 보기")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(vm.watchLaterUIDs.count)개")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.md)
            Divider()
            if vm.watchLaterUIDs.isEmpty {
                emptyPopoverState(icon: "bookmark", message: "북마크한 클립이 없어요")
            } else if clips.isEmpty {
                emptyPopoverState(
                    icon: "arrow.clockwise",
                    message: "현재 목록에 보이는 클립이 없어요.\n인기 클립이나 채널 클립을 먼저 불러와 주세요"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(clips, id: \.clipUID) { clip in
                            popoverClipRow(
                                clip: clip,
                                trailingIcon: "bookmark.slash",
                                onSelect: {
                                    showWatchLaterPopover = false
                                    vm.playClip(clip)
                                },
                                onTrailing: { vm.toggleWatchLater(clip) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .background(DesignTokens.Colors.surfaceBase)
    }

    /// 현재 메모리에 로드된 클립(인기/채널/큐) 중에서 watch later UID에 해당하는 것을 모은다.
    /// [2026-04-30 Phase5] 메모리에 없으면 savedClipSnapshots에서 fallback 복원.
    private func collectWatchLaterClips() -> [ClipInfo] {
        guard !vm.watchLaterUIDs.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [ClipInfo] = []
        for clip in vm.trendingClips + vm.channelClips + vm.queueClips {
            if vm.watchLaterUIDs.contains(clip.clipUID), !seen.contains(clip.clipUID) {
                seen.insert(clip.clipUID)
                out.append(clip)
            }
        }
        // Snapshot fallback — 메모리 목록에 없는 저장 클립 복원
        for uid in vm.watchLaterUIDs where !seen.contains(uid) {
            if let snap = vm.savedClipSnapshots[uid] {
                seen.insert(uid)
                out.append(snap)
            }
        }
        return out
    }

    private func popoverClipRow(
        clip: ClipInfo,
        trailingIcon: String,
        onSelect: @escaping () -> Void,
        onTrailing: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button(action: onSelect) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let url = clip.thumbnailImageURL {
                        CachedAsyncImage(url: url) {
                            Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                        }
                        .frame(width: 56, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    } else {
                        Rectangle()
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 56, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.clipTitle)
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(2)
                        if let name = clip.channel?.channelName {
                            Text(name)
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .customCursor(.pointingHand)

            Button(action: onTrailing) {
                Image(systemName: trailingIcon)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .customCursor(.pointingHand)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func emptyPopoverState(icon: String, message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(message)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.md)
    }

    private var tabBar: some View {
        // [2026-04-30 Pass2] 탭바 정밀화
        //   - 액티브 탭: 아이콘 옆 작은 라이브 도트 + 그라디언트 underline (그린→그린 0.5)
        //   - 카운트 배지(인기 클립 개수) 우측 표시 — 컨텍스트 가독성 향상
        HStack(spacing: 0) {
            ForEach(ClipBrowser.ClipTab.allCases) { tab in
                Button {
                    withAnimation(DesignTokens.Animation.indicator) {
                        vm.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(DesignTokens.Typography.custom(size: 11.5, weight: vm.selectedTab == tab ? .semibold : .medium))
                            Text(tab.rawValue)
                                .font(DesignTokens.Typography.custom(size: 12.5, weight: vm.selectedTab == tab ? .semibold : .medium))
                            if let count = tabCount(tab) {
                                Text("\(count)")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(
                                        vm.selectedTab == tab
                                            ? DesignTokens.Colors.chzzkGreen
                                            : DesignTokens.Colors.textTertiary
                                    )
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(
                                            (vm.selectedTab == tab
                                                ? DesignTokens.Colors.chzzkGreen
                                                : DesignTokens.Colors.textTertiary)
                                            .opacity(0.12)
                                        )
                                    )
                            }
                        }
                        .foregroundStyle(vm.selectedTab == tab
                                         ? DesignTokens.Colors.chzzkGreen
                                         : DesignTokens.Colors.textSecondary)
                        .padding(.vertical, 8)
                        .animation(DesignTokens.Animation.indicator, value: vm.selectedTab)

                        ZStack {
                            // 기본 아래 선 — 모든 탭 공통
                            Rectangle()
                                .fill(DesignTokens.Glass.borderColorLight.opacity(0.4))
                                .frame(height: 1)
                            if vm.selectedTab == tab {
                                // 선택된 탭 underline (두껍고 입체감 있는 capsule)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                DesignTokens.Colors.chzzkGreen,
                                                DesignTokens.Colors.chzzkGreen.opacity(0.55)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 2.5)
                                    .padding(.horizontal, 28)
                                    .matchedGeometryEffect(id: "clipTabUnderline", in: tabNS)
                                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.45), radius: 4, y: 1)
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .contentBackground()
    }

    /// 탭 옆 카운트 배지에 표시할 값. 빈 상태일 때는 nil.
    private func tabCount(_ tab: ClipBrowser.ClipTab) -> Int? {
        switch tab {
        case .trending:
            return vm.trendingClips.isEmpty ? nil : vm.trendingClips.count
        case .channel:
            if vm.channelClips.isEmpty { return nil }
            return vm.channelTotalCount ?? vm.channelClips.count
        }
    }

    // MARK: - 전체 인기클립 컨텐츠

    private func trendingContent(inspectorAvailable: Bool) -> some View {
        Group {
            if vm.trendingIsLoading && vm.trendingClips.isEmpty {
                loadingView(message: "치지직 인기 클립을 불러오는 중...")
            } else if let error = vm.trendingError, vm.trendingClips.isEmpty {
                errorView(error) { Task { await vm.loadTrendingClips() } }
            } else if vm.trendingClips.isEmpty {
                trendingEmptyView
            } else {
                trendingGallery(inspectorAvailable: inspectorAvailable)
            }
        }
    }

    /// Spotlight + grid/list. Spotlight는 grid 모드일 때만 노출.
    private func trendingGallery(inspectorAvailable: Bool) -> some View {
        let allClips = vm.trendingClips
        let pageSlice = vm.displayedTrendingClips
        let isFirstPage = vm.trendingDisplayPage == 0

        // grid 모드 첫 페이지: 첫 클립을 spotlight, 나머지를 그리드로
        let spotlight: ClipInfo? = (vm.viewMode == .grid && isFirstPage) ? allClips.first : nil
        let restSlice: ArraySlice<ClipInfo> = {
            if let spot = spotlight {
                // 첫 페이지에서 spotlight(=clips[0])를 제외하고 나머지 슬라이스
                return pageSlice.dropFirst(pageSlice.first?.clipUID == spot.clipUID ? 1 : 0)
            }
            return pageSlice
        }()

        return ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                if let spotlight {
                    SpotlightClipCard(clip: spotlight) {
                        vm.handleClipTap(spotlight, inspectorAvailable: inspectorAvailable)
                    } onPlay: {
                        vm.playClip(spotlight)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                }

                clipListInline(
                    clips: restSlice,
                    showChannelBadge: true,
                    inspectorAvailable: inspectorAvailable
                )

                trendingPaginationBar
                    .padding(.vertical, DesignTokens.Spacing.md)
            }
        }
    }

    private var trendingEmptyView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.accentPink.opacity(0.18),
                                DesignTokens.Colors.accentOrange.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .overlay { Circle().strokeBorder(DesignTokens.Colors.accentPink.opacity(0.30), lineWidth: 0.7) }
                    .shadow(color: DesignTokens.Colors.accentPink.opacity(0.18), radius: 12, y: 4)
                Image(systemName: "flame.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DesignTokens.Colors.accentPink, DesignTokens.Colors.accentOrange],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            VStack(spacing: 4) {
                Text("인기 클립을 불러올 수 없습니다")
                    .font(DesignTokens.Typography.bodyMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("잠시 후 다시 시도해 주세요")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Button { Task { await vm.loadTrendingClips() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("새로고침")
                }
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(DesignTokens.Colors.chzzkGreen, in: Capsule())
                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.96))
            .customCursor(.pointingHand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 채널별 클립 컨텐츠

    private func channelContent(inspectorAvailable: Bool) -> some View {
        Group {
            if vm.channelIsLoading && vm.channelClips.isEmpty {
                loadingView(message: "클립을 불러오는 중...")
            } else if let error = vm.channelError, vm.channelClips.isEmpty {
                errorView(error) { vm.loadChannelClips(reset: true) }
            } else if vm.channelClips.isEmpty {
                channelEmptyView
            } else {
                VStack(spacing: 0) {
                    channelHeaderBar
                    clipListPaged(
                        clips: vm.displayedChannelClips,
                        showChannelBadge: false,
                        inspectorAvailable: inspectorAvailable
                    )
                }
            }
        }
    }

    /// [2026-04-30 Phase3] 채널 콘텐츠 헤더 — 뒤로가기 + 채널 메타 + 통계.
    private var channelHeaderBar: some View {
        let channelInfo = vm.channelClips.first?.channel
        let channelName = channelInfo?.channelName ?? vm.channelInput
        return HStack(spacing: DesignTokens.Spacing.md) {
            // 뒤로가기
            Button {
                vm.clearChannelSelection()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text("다른 채널").font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DesignTokens.Colors.chzzkGreen.opacity(0.10), in: Capsule())
                .overlay { Capsule().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 0.6) }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.96))
            .customCursor(.pointingHand)

            if let url = channelInfo?.channelImageURL {
                CachedAsyncImage(url: url) {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.4), lineWidth: 0.7) }
            }

            Text(channelName.isEmpty ? "채널" : channelName)
                .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            if let total = vm.channelTotalCount {
                Text("\(total)개")
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
            }

            Spacer()

            if vm.channelIsLoading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("불러오는 중")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Glass.borderColorLight.opacity(0.35))
                .frame(height: 0.5)
        }
    }

    /// [2026-04-30 Phase2 정밀 재설계] 채널 탭 빈 화면 — Hero + 최근 채널 + 팔로잉 + 가이드.
    private var channelEmptyView: some View {
        let following = appState.homeViewModel?.followingChannels ?? []

        return ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                // ── Hero
                channelEmptyHero
                    .padding(.top, DesignTokens.Spacing.xl)

                // ── 최근 채널
                if !vm.recentChannels.isEmpty {
                    channelEmptySection(
                        title: "최근 본 채널",
                        icon: "clock.arrow.circlepath",
                        accent: DesignTokens.Colors.accentBlue,
                        trailing: AnyView(
                            Button { vm.clearRecentChannels() } label: {
                                Text("기록 지우기")
                                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .customCursor(.pointingHand)
                        )
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(vm.recentChannels, id: \.channelId) { ch in
                                    channelQuickCard(
                                        channelId: ch.channelId,
                                        channelName: ch.channelName,
                                        imageURL: ch.channelImageURL,
                                        isLive: false,
                                        verified: ch.verifiedMark,
                                        accent: DesignTokens.Colors.accentBlue
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }

                // ── 팔로잉
                if !following.isEmpty {
                    channelEmptySection(
                        title: "팔로잉 중인 채널",
                        icon: "person.2.fill",
                        accent: DesignTokens.Colors.chzzkGreen,
                        trailing: AnyView(
                            Text("\(following.count)")
                                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(DesignTokens.Colors.chzzkGreen.opacity(0.12), in: Capsule())
                        )
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(following.prefix(12), id: \.id) { ch in
                                    channelQuickCard(
                                        channelId: ch.channelId,
                                        channelName: ch.channelName,
                                        imageURL: ch.channelImageUrl.flatMap { URL(string: $0) },
                                        isLive: ch.isLive,
                                        verified: false,
                                        accent: DesignTokens.Colors.chzzkGreen
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }

                // ── 가이드
                channelEmptyGuide
                    .padding(.bottom, DesignTokens.Spacing.xl)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
    }

    /// Hero — 큰 아이콘 + 타이틀 + 서브타이틀 + 검색 버튼.
    private var channelEmptyHero: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.chzzkGreen.opacity(0.20),
                                DesignTokens.Colors.accentBlue.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                    .overlay { Circle().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.30), lineWidth: 0.8) }
                    .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.20), radius: 14, y: 4)
                Image(systemName: "film.stack")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.accentBlue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 5) {
                Text("채널을 선택해 보세요")
                    .font(DesignTokens.Typography.custom(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("채널 ID, URL, 또는 채널명으로 검색 · 팔로잉/최근 채널에서 빠르게 선택")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 빈 화면 섹션 헤더 + 콘텐츠 묶음.
    private func channelEmptySection<Content: View>(
        title: String,
        icon: String,
        accent: Color,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
    }

    /// 채널 빠른 접근 카드 — 아바타 + 이름 + (라이브 도트).
    private func channelQuickCard(
        channelId: String,
        channelName: String,
        imageURL: URL?,
        isLive: Bool,
        verified: Bool,
        accent: Color
    ) -> some View {
        Button {
            vm.selectChannelSuggestion(channelId: channelId, channelName: channelName)
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let imageURL {
                        CachedAsyncImage(url: imageURL) {
                            Circle().fill(DesignTokens.Colors.surfaceElevated)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(accent.opacity(0.35), lineWidth: 0.7) }
                    } else {
                        Circle()
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                    }
                    if isLive {
                        Circle()
                            .fill(DesignTokens.Colors.accentPink)
                            .frame(width: 8, height: 8)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1.2) }
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(channelName)
                            .font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        if verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(accent)
                        }
                    }
                    if isLive {
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 8.5, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.accentPink)
                    } else {
                        Text(channelId.prefix(10) + (channelId.count > 10 ? "…" : ""))
                            .font(DesignTokens.Typography.custom(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(maxWidth: 140, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accent.opacity(0.20), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))
        .customCursor(.pointingHand)
    }

    /// 가이드 — 채널 ID 찾는 방법.
    private var channelEmptyGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                Text("채널 ID를 찾는 방법")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            VStack(alignment: .leading, spacing: 5) {
                guideItem(num: "1", text: "채널 페이지 URL 끝의 ID 복사",
                          mono: "chzzk.naver.com/{channelId}")
                guideItem(num: "2", text: "검색창에 채널명 직접 입력 → 자동완성 선택")
                guideItem(num: "3", text: "팔로잉 채널은 위의 카드에서 클릭")
            }
            .padding(DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.45), lineWidth: 0.6)
            }
        }
    }

    @ViewBuilder
    private func guideItem(num: String, text: String, mono: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(num)
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(DesignTokens.Colors.accentOrange.opacity(0.85), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if let mono {
                    Text(mono)
                        .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(DesignTokens.Colors.surfaceBase.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    // MARK: - 공용 클립 목록 뷰

    /// trending용. ScrollView 없이 inline로 그리드/리스트를 그린다 (Spotlight와 같은 ScrollView 안에 배치).
    private func clipListInline(clips: ArraySlice<ClipInfo>, showChannelBadge: Bool, inspectorAvailable: Bool) -> some View {
        Group {
            switch vm.viewMode {
            case .grid:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230), spacing: DesignTokens.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(clips, id: \.clipUID) { clip in
                        EquatableClipGridCard(
                            clip: clip,
                            showChannel: showChannelBadge,
                            isSelected: vm.previewClip?.clipUID == clip.clipUID
                        ) {
                            vm.handleClipTap(clip, inspectorAvailable: inspectorAvailable)
                        }
                        .equatable()
                    }
                }
                .padding(DesignTokens.Spacing.md)
            case .list:
                LazyVStack(spacing: 1) {
                    ForEach(clips, id: \.clipUID) { clip in
                        EquatableClipListRow(
                            clip: clip,
                            isSelected: vm.previewClip?.clipUID == clip.clipUID
                        ) {
                            vm.handleClipTap(clip, inspectorAvailable: inspectorAvailable)
                        }
                        .equatable()
                    }
                }
                .padding(DesignTokens.Spacing.sm)
            }
        }
    }

    /// [2026-04-30 Phase3] 채널 클립 페이지 표시 — 한 페이지(24개)만 렌더링하여 누적 비용 제거.
    private func clipListPaged(clips: ArraySlice<ClipInfo>, showChannelBadge: Bool, inspectorAvailable: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    switch vm.viewMode {
                    case .grid:
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 230), spacing: DesignTokens.Spacing.md)],
                            alignment: .leading,
                            spacing: DesignTokens.Spacing.md
                        ) {
                            ForEach(clips, id: \.clipUID) { clip in
                                EquatableClipGridCard(
                                    clip: clip,
                                    showChannel: showChannelBadge,
                                    isSelected: vm.previewClip?.clipUID == clip.clipUID
                                ) {
                                    vm.handleClipTap(clip, inspectorAvailable: inspectorAvailable)
                                }
                                .equatable()
                            }
                        }
                        .padding(DesignTokens.Spacing.md)
                    case .list:
                        LazyVStack(spacing: 1) {
                            ForEach(clips, id: \.clipUID) { clip in
                                EquatableClipListRow(
                                    clip: clip,
                                    isSelected: vm.previewClip?.clipUID == clip.clipUID
                                ) {
                                    vm.handleClipTap(clip, inspectorAvailable: inspectorAvailable)
                                }
                                .equatable()
                            }
                        }
                        .padding(DesignTokens.Spacing.sm)
                    }
                }

                // 페이지 컨트롤
                channelPaginationBar
                    .padding(.vertical, DesignTokens.Spacing.md)
            }
        }
        .scrollIndicators(.automatic)
    }

    /// 채널 페이지네이션 바 — 이전/현재/다음 + 페이지 N/M.
    private var channelPaginationBar: some View {
        let cur = vm.channelDisplayPage
        let total = vm.channelTotalDisplayPages
        let canPrev = cur > 0
        let canNext = cur < total - 1 || vm.channelHasMore

        return HStack(spacing: DesignTokens.Spacing.md) {
            paginationButton(
                icon: "chevron.left",
                label: "이전",
                enabled: canPrev
            ) {
                vm.goToChannelDisplayPage(cur - 1)
            }

            HStack(spacing: 6) {
                Text("\(cur + 1)")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("/")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("\(total)\(vm.channelHasMore ? "+" : "")")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
            .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.45), lineWidth: 0.6) }

            paginationButton(
                icon: "chevron.right",
                label: "다음",
                enabled: canNext,
                trailing: true,
                loading: vm.channelIsLoading && cur >= total - 1
            ) {
                vm.goToChannelDisplayPage(cur + 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 인기 클립 페이지네이션 바.
    private var trendingPaginationBar: some View {
        let cur = vm.trendingDisplayPage
        let total = vm.trendingTotalDisplayPages
        guard total > 1 else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: DesignTokens.Spacing.md) {
                paginationButton(icon: "chevron.left", label: "이전", enabled: cur > 0) {
                    vm.goToTrendingDisplayPage(cur - 1)
                }
                HStack(spacing: 6) {
                    Text("\(cur + 1)")
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.accentPink)
                    Text("/")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("\(total)")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, 5)
                .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.45), lineWidth: 0.6) }
                paginationButton(icon: "chevron.right", label: "다음", enabled: cur < total - 1, trailing: true) {
                    vm.goToTrendingDisplayPage(cur + 1)
                }
            }
            .frame(maxWidth: .infinity)
        )
    }

    /// 페이지 이전/다음 버튼.
    private func paginationButton(
        icon: String,
        label: String,
        enabled: Bool,
        trailing: Bool = false,
        loading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !trailing {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold))
                }
                Text(label).font(DesignTokens.Typography.custom(size: 11.5, weight: .semibold))
                if trailing {
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: icon).font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .foregroundStyle(enabled ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary.opacity(0.55))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                (enabled ? DesignTokens.Colors.surfaceElevated : DesignTokens.Colors.surfaceBase.opacity(0.4)),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    enabled ? DesignTokens.Glass.borderColorLight.opacity(0.55) : DesignTokens.Glass.borderColorLight.opacity(0.18),
                    lineWidth: 0.6
                )
            }
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        .disabled(!enabled)
        .customCursor(enabled ? .pointingHand : .arrow)
    }

    // MARK: - 공용 상태 뷰

    private func loadingView(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView().controlSize(.large).tint(DesignTokens.Colors.chzzkGreen)
            Text(message).font(DesignTokens.Typography.captionMedium).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.accentOrange.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
            }
            Text(error).font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도", action: retry).buttonStyle(.bordered).tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

