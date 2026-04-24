// MARK: - MLSingleChannelStage.swift
// 멀티라이브 "탭 모드" 또는 단일 활성 세션을 풀-임베드로 표시하는 스테이지.
// 일반 라이브 메뉴(LiveStreamView) 와 비슷한 풍부한 헤더 오버레이(채널 프로필 + 채널명 + 라이브 제목 + 시청자수)
// 를 제공해 "채널별 싱글 화면" 처럼 보이도록 한다.
//
// MLPlayerPane 위에 자동 페이드 헤더 오버레이를 합성한다.
// 호버 / 탭 시 헤더가 페이드인 → 일정 시간 후 자동 페이드아웃.

import SwiftUI
import CViewCore
import CViewUI

struct MLSingleChannelStage: View {
    let session: MultiLiveSession
    let manager: MultiLiveManager
    let appState: AppState

    @State private var isHeaderVisible: Bool = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            // ── 비디오 영역 (기존 MLPlayerPane 재사용) ──
            MLPlayerPane(session: session, manager: manager, appState: appState, isActive: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // [2026-04-22] 헤더 오버레이 제거 — 탭 칩이 이미 채널 프로필·채널명·LIVE 상태·
            // 라이브 제목·시청자 수를 모두 표시하므로 영상 위 헤더가 중복 겹침의 원인.
            // 자동 페이드 hover 로직도 불필요해 상태/타이머도 제거.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerOverlay: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            // 채널 프로필
            if let url = session.profileImageURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(DesignTokens.Colors.surfaceElevated)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !session.isOffline {
                        Text("LIVE")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(DesignTokens.Colors.error)
                            )
                    }
                    Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                        .font(DesignTokens.Typography.custom(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if !session.liveTitle.isEmpty {
                    Text(session.liveTitle)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            // 시청자 / 누적
            HStack(spacing: DesignTokens.Spacing.sm) {
                if session.viewerCount > 0 {
                    Label {
                        Text(session.formattedViewerCount)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .rounded))
                    } icon: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .help("현재 시청자 수")
                }
                if session.accumulateCount > 0 {
                    Label {
                        Text(session.formattedAccumulateCount)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .rounded))
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .help("누적 시청자 수")
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm + 2)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Auto-hide

    private func showHeader() {
        hideTask?.cancel()
        if !isHeaderVisible {
            withAnimation(DesignTokens.Animation.snappy) {
                isHeaderVisible = true
            }
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(DesignTokens.Animation.contentTransition) {
                isHeaderVisible = false
            }
        }
    }
}
