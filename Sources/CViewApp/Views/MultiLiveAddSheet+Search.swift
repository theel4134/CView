// MARK: - MultiLiveAddSheet+Search.swift
// CViewApp — 멀티라이브 추가 시트: 검색 탭

import SwiftUI
import CViewCore
import CViewNetworking

extension MultiLiveAddSheet {

    // MARK: - 검색 탭

    var searchContent: some View {
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

    var searchField: some View {
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

    var searchResultsList: some View {
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

    func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("\(count)")
                .font(DesignTokens.Typography.custom(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(DesignTokens.Colors.surfaceOverlay.opacity(0.4)))
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    var searchPromptView: some View {
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

    var noResultsView: some View {
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

    func liveSearchRow(live: LiveInfo) -> some View {
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

    func channelSearchRow(channel: ChannelInfo) -> some View {
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
}
