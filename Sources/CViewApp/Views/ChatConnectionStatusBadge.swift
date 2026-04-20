// MARK: - ChatConnectionStatusBadge.swift
// CViewApp - 채팅 연결 상태(연결/연결중/재연결 attempt/끊김) 시각화 헬퍼
// 멀티채팅 그리드 셀 헤더, 통합 채팅 푸터, 사이드바 등에서 공용 사용

import SwiftUI
import CViewCore
import CViewUI

/// 작은 점 + 상태 라벨 배지 — 그리드 셀 헤더용 (높이 ~12pt)
struct ChatConnectionStatusBadge: View {
    let state: ChatConnectionState
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            statusIndicator
            if let label = badgeLabel {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                    .foregroundStyle(badgeColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state {
        case .reconnecting:
            // 회전 애니메이션 아이콘으로 진행 중임을 명확히 표시
            RotatingArrowsIcon()
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                .foregroundStyle(badgeColor)
        case .connecting:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(compact ? 0.5 : 0.6)
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
        default:
            Circle()
                .fill(badgeColor)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
        }
    }

    private var badgeColor: Color {
        switch state {
        case .connected:
            return DesignTokens.Colors.chzzkGreen
        case .connecting, .reconnecting:
            return DesignTokens.Colors.warning
        case .disconnected, .failed:
            return DesignTokens.Colors.error
        }
    }

    private var badgeLabel: String? {
        switch state {
        case .reconnecting(let attempt) where attempt > 0:
            return "재연결 \(attempt)"
        case .connecting:
            return compact ? nil : "연결 중"
        case .failed:
            return compact ? nil : "실패"
        default:
            return nil
        }
    }
}

/// 무한 회전 화살표 아이콘 — 재연결 진행 시 표시
///
/// [GPU 누적 부하 수정] withAnimation(...repeatForever) onAppear 패턴을 SF Symbol
/// `.rotate` symbol effect 로 교체. 기존 구현은 멀티채팅에서 N개 셀이 reconnecting
/// 상태에 진입/이탈을 반복할 때마다 새 implicit animation 이 추가되어 Core Animation
/// 레이어에 누적될 위험이 있었음. symbolEffect 는 Core Animation 단일 레이어를
/// 직접 회전하므로 누적이 없고 GPU 비용이 일정.
private struct RotatingArrowsIcon: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 8, weight: .bold))
            .symbolEffect(.rotate, options: .repeat(.continuous))
    }
}
