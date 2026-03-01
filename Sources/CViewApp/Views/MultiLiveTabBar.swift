// MARK: - MultiLiveTabBar.swift
// CViewApp — 멀티라이브 하단 세션 탭바

import SwiftUI
import CViewCore

struct MultiLiveTabBar: View {

    @Bindable var manager: MultiLiveManager

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(manager.sessions) { session in
                tabItem(session: session)
            }

            if manager.canAddSession {
                addButton
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                .frame(height: 0.5)
        }
    }

    // MARK: - 탭 아이템

    private func tabItem(session: MultiLiveSession) -> some View {
        let isSelected = session.id == manager.selectedSessionId

        return HStack(spacing: DesignTokens.Spacing.xs) {
            // 프로필 이미지
            AsyncImage(url: session.profileImageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(session.channelName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)

                // 상태 표시
                HStack(spacing: 2) {
                    statusIndicator(for: session)
                    if session.loadState == .playing {
                        Text("\(session.viewerCount)")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            // 닫기 버튼
            Button {
                Task {
                    await manager.removeSession(id: session.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DesignTokens.Animation.normal) {
                manager.selectSession(id: session.id)
            }
        }
    }

    // MARK: - 상태 인디케이터

    @ViewBuilder
    private func statusIndicator(for session: MultiLiveSession) -> some View {
        switch session.loadState {
        case .playing:
            Circle()
                .fill(DesignTokens.Colors.chzzkGreen)
                .frame(width: 6, height: 6)
        case .loading:
            ProgressView()
                .controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .idle:
            Circle()
                .fill(DesignTokens.Colors.textTertiary)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - 추가 버튼

    private var addButton: some View {
        Button {
            manager.showAddSheet = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 36)
        .help("채널 추가 (\(manager.sessions.count)/\(MultiLiveManager.maxSessions))")
    }
}
