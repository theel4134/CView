// MARK: - MultiLiveTabBar.swift
// CViewApp — 멀티라이브 하단 세션 탭바

import SwiftUI
import CViewCore

struct MultiLiveTabBar: View {

    @Bindable var manager: MultiLiveManager
    @Namespace private var tabSelection
    @State private var hoveredSessionId: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(manager.sessions) { session in
                tabItem(session: session)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
            }

            if manager.canAddSession {
                addButton
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                .frame(height: 0.5)
        }
        .animation(DesignTokens.Animation.spring, value: manager.sessions.map(\.id))
    }

    // MARK: - 탭 아이템

    private func tabItem(session: MultiLiveSession) -> some View {
        let isSelected = session.id == manager.selectedSessionId
        let isHovered = hoveredSessionId == session.id

        return HStack(spacing: 8) {
            // 프로필 이미지
            AsyncImage(url: session.profileImageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay {
                if session.loadState == .playing {
                    Circle()
                        .strokeBorder(DesignTokens.Colors.chzzkGreen, lineWidth: 1.5)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(session.channelName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)

                HStack(spacing: 3) {
                    statusIndicator(for: session)
                    if session.loadState == .playing {
                        Text("\(session.viewerCount)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            // 닫기 버튼 (호버 시에만 표시)
            if isHovered || isSelected {
                Button {
                    Task {
                        await manager.removeSession(id: session.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(.white.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                    }
                    .matchedGeometryEffect(id: "tabBG", in: tabSelection)
            } else if isHovered {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(.white.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DesignTokens.Animation.snappy) {
                manager.selectSession(id: session.id)
            }
        }
        .onHover { hover in
            withAnimation(DesignTokens.Animation.fast) {
                hoveredSessionId = hover ? session.id : nil
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
                .frame(width: 5, height: 5)
        case .loading:
            ProgressView()
                .controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
        case .idle:
            Circle()
                .fill(DesignTokens.Colors.textTertiary.opacity(0.5))
                .frame(width: 5, height: 5)
        }
    }

    // MARK: - 추가 버튼

    private var addButton: some View {
        Button {
            manager.showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
        .help("채널 추가 (\(manager.sessions.count)/\(MultiLiveManager.maxSessions))")
    }
}
