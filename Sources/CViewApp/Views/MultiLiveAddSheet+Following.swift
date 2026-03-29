// MARK: - MultiLiveAddSheet+Following.swift
// CViewApp — 멀티라이브 추가 시트: 팔로잉 탭

import SwiftUI
import CViewCore
import CViewNetworking

extension MultiLiveAddSheet {

    // MARK: - 팔로잉 탭

    var followingContent: some View {
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

    var filteredFollowingChannels: [LiveChannelItem] {
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

    var followingList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(filteredFollowingChannels) { channel in
                    followingRow(channel: channel)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
    }

    func followingRow(channel: LiveChannelItem) -> some View {
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
                                Circle().strokeBorder(DesignTokens.Colors.surfaceOverlay, lineWidth: 1.5)
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

    var followingEmptyView: some View {
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
}
