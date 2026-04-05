// MARK: - MultiLiveAddSheet+Following.swift
// CViewApp — 멀티라이브 추가 시트: 팔로잉 콘텐츠

import SwiftUI
import CViewCore
import CViewNetworking

extension MultiLiveAddSheet {

    // MARK: - 팔로잉 필터

    var filteredFollowingChannels: [LiveChannelItem] {
        var channels = followingChannels
        if showLiveOnly {
            channels = channels.filter { $0.isLive }
        }
        // 라이브 채널 상단 정렬 (라이브 우선, 시청자 수 내림차순)
        return channels.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            return a.viewerCount > b.viewerCount
        }
    }

    // MARK: - 팔로잉 리스트

    var followingList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(Array(filteredFollowingChannels.enumerated()), id: \.element.id) { index, channel in
                    followingRow(channel: channel)
                        .scrollTransition(.animated(DesignTokens.Animation.smooth)) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0)
                                .scaleEffect(phase.isIdentity ? 1 : 0.96, anchor: .leading)
                                .offset(y: phase.isIdentity ? 0 : 8)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.96, anchor: .top))
                                    .animation(DesignTokens.Animation.cardAppear.delay(min(Double(index) * 0.03, 0.15))),
                                removal: .opacity.animation(DesignTokens.Animation.fast)
                            )
                        )
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
                            .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.6), radius: 3, x: 0, y: 0)
                            .overlay {
                                Circle().strokeBorder(DesignTokens.Colors.surfaceOverlay, lineWidth: 1.5)
                            }
                            .transition(.scale.combined(with: .opacity))
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
                            .contentTransition(.numericText())
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
                .phaseAnimator([false, true]) { content, phase in
                    content
                        .scaleEffect(phase ? 1.08 : 1.0)
                        .opacity(phase ? 0.55 : 1.0)
                } animation: { _ in
                    .easeInOut(duration: 2.2)
                }
            VStack(spacing: 4) {
                Text("팔로잉 채널이 없습니다")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("로그인 후 팔로잉한 채널이 여기에 표시됩니다")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
