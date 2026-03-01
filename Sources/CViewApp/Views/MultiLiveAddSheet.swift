// MARK: - MultiLiveAddSheet.swift
// CViewApp — 멀티라이브 채널 추가 시트
// 라이브 검색 + 채널 ID 직접 입력

import SwiftUI
import CViewCore
import CViewNetworking

struct MultiLiveAddSheet: View {

    @Bindable var manager: MultiLiveManager
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [LiveInfo] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var channelIdInput = ""
    @State private var addError: String?
    @State private var addingChannelId: String?
    @State private var recentlyAddedIds: Set<String> = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedTab: AddSheetTab = .search

    private enum AddSheetTab: String, CaseIterable {
        case search = "라이브 검색"
        case direct = "채널 ID"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            
            // 콘텐츠
            Group {
                switch selectedTab {
                case .search:
                    searchContent
                case .direct:
                    directInputContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            // 하단 에러 메시지
            if let error = addError {
                errorBanner(error)
            }
        }
        .frame(width: 460, height: 520)
        .background(DesignTokens.Colors.backgroundElevated)
        .onChange(of: searchQuery) {
            debounceSearch()
        }
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
                Text("최대 \(MultiLiveManager.maxSessions)개 채널 동시 시청")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            // 세션 카운터
            sessionCounter

            Button {
                dismiss()
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
            ForEach(0..<MultiLiveManager.maxSessions, id: \.self) { i in
                Circle()
                    .fill(i < manager.sessions.count ? DesignTokens.Colors.chzzkGreen : .white.opacity(0.1))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.06)))
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
                    Text(tab.rawValue)
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
                    .frame(width: tabWidth * 0.6, height: 2)
                    .clipShape(Capsule())
                    .offset(x: tabWidth * CGFloat(index) + tabWidth * 0.2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(.white.opacity(0.03))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                .frame(height: 0.5)
        }
    }

    // MARK: - 검색 탭 콘텐츠

    private var searchContent: some View {
        VStack(spacing: 0) {
            // 검색 필드
            searchField
                .padding(DesignTokens.Spacing.md)

            // 결과 영역
            if isSearching {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(DesignTokens.Colors.chzzkGreen)
                Spacer()
            } else if searchResults.isEmpty && hasSearched {
                Spacer()
                noResultsView
                Spacer()
            } else if !searchResults.isEmpty {
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
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(searchResults) { live in
                    liveSearchRow(live: live)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
    }

    private var searchPromptView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "tv")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("현재 진행 중인 라이브를 검색하세요")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private var noResultsView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("검색 결과가 없습니다")
                .font(.callout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("다른 검색어를 시도하거나 채널 ID를 직접 입력하세요")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - 검색 결과 행

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
                        Rectangle().fill(.white.opacity(0.06))
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
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                    Text("\(live.concurrentUserCount)")
                        .font(.caption.weight(.medium).monospacedDigit())
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)

                // 추가 상태
                Group {
                    if isAddingThis {
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
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(DesignTokens.Colors.chzzkGreen))
                            .frame(width: 44)
                    }
                }
                .animation(DesignTokens.Animation.fast, value: alreadyAdded)
                .animation(DesignTokens.Animation.fast, value: isAddingThis)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(.white.opacity(0.03))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(.white.opacity(0.04), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded || isAddingThis || !manager.canAddSession)
        .opacity(alreadyAdded ? 0.5 : 1.0)
    }

    // MARK: - 직접 입력 탭 콘텐츠

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
                        .fill(.white.opacity(0.05))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
                }

                Button {
                    let id = channelIdInput.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    addChannel(channelId: id)
                } label: {
                    Group {
                        if addingChannelId != nil {
                            ProgressView()
                                .controlSize(.small)
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

            // 추가된 세션 목록 (현재 세션)
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
                                .fill(.white.opacity(0.03))
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

    private func debounceSearch() {
        searchDebounceTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
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

        Task {
            do {
                let result = try await apiClient.searchLives(keyword: query, size: 15)
                withAnimation(DesignTokens.Animation.normal) {
                    searchResults = result.data
                    hasSearched = true
                }
            } catch {
                withAnimation(DesignTokens.Animation.normal) {
                    searchResults = []
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
            await manager.addSession(channelId: channelId)
            withAnimation(DesignTokens.Animation.spring) {
                recentlyAddedIds.insert(channelId)
                addingChannelId = nil
            }
            channelIdInput = ""

            if !manager.canAddSession {
                try? await Task.sleep(for: .milliseconds(300))
                dismiss()
            }
        }
    }
}
