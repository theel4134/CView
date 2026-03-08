// MARK: - MultiLiveTabBar.swift
// CViewApp — 멀티라이브 상단 세션 탭바

import SwiftUI
import CViewCore

struct MultiLiveTabBar: View {

    @Bindable var manager: MultiLiveManager
    @Namespace private var tabSelection
    @State private var hoveredSessionId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // 탭 영역
            HStack(spacing: 2) {
                ForEach(manager.sessions, id: \.id) { session in
                    tabItem(session: session)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity)
                        ))
                }
            }

            // 추가 버튼
            if manager.canAddSession {
                addButton
                    .padding(.leading, 6)
            }

            Spacer(minLength: 0)

            // 세션 카운터
            Text("\(manager.sessions.count)/\(MultiLiveManager.maxSessions)")
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background {
            Rectangle()
                .fill(.black.opacity(0.4))
                .background(.ultraThinMaterial)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                .frame(height: 0.5)
        }
            .animation(DesignTokens.Animation.contentTransition, value: manager.sessions.count)
    }

    // MARK: - 탭 아이템

    private func tabItem(session: MultiLiveSession) -> some View {
        let isSelected = session.id == manager.selectedSessionId
        let isHovered = hoveredSessionId == session.id

        return HStack(spacing: 6) {
            // 상태 + 프로필
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: session.profileImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 14))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())

                statusDot(for: session)
                    .offset(x: 2, y: 2)
            }

            Text(session.channelName)
                .font(DesignTokens.Typography.custom(size: 12, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)

            // 시청자 수 (재생 중일 때)
            if session.loadState == .playing {
                Text(formatViewerCount(session.viewerCount))
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            // 닫기 버튼 (호버 시)
            if isHovered {
                Button {
                    Task {
                        await manager.removeSession(id: session.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.custom(size: 7, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                Capsule()
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                    }
                    .matchedGeometryEffect(id: "tabBG", in: tabSelection)
            } else if isHovered {
                Capsule()
                    .fill(.white.opacity(0.06))
            }
        }
        .contentShape(Capsule())
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
        .cursor(.pointingHand)
    }

    // MARK: - 상태 도트

    @ViewBuilder
    private func statusDot(for session: MultiLiveSession) -> some View {
        switch session.loadState {
        case .playing:
            Circle()
                .fill(DesignTokens.Colors.chzzkGreen)
                .frame(width: 6, height: 6)
                .overlay {
                    Circle().strokeBorder(.black, lineWidth: 1)
                }
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
                .frame(width: 6, height: 6)
        case .error:
            Circle()
                .fill(DesignTokens.Colors.accentOrange)
                .frame(width: 6, height: 6)
                .overlay {
                    Circle().strokeBorder(.black, lineWidth: 1)
                }
        case .idle:
            Circle()
                .fill(DesignTokens.Colors.textTertiary.opacity(0.5))
                .frame(width: 6, height: 6)
                .overlay {
                    Circle().strokeBorder(.black, lineWidth: 1)
                }
        }
    }

    // MARK: - 추가 버튼

    private var addButton: some View {
        Button {
            manager.showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help("채널 추가")
        .cursor(.pointingHand)
    }

    // MARK: - Helpers

    private func formatViewerCount(_ count: Int) -> String {
        if count >= 10000 {
            return "\(count / 10000).\((count % 10000) / 1000)만"
        } else if count >= 1000 {
            return "\(count / 1000).\((count % 1000) / 100)천"
        }
        return "\(count)"
    }
}
