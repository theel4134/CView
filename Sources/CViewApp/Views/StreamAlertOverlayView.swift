// MARK: - StreamAlertOverlayView.swift
// 플레이어 화면 위에 표시되는 후원/구독/공지 알림 오버레이

import SwiftUI
import CViewCore

/// 플레이어 영역 위에 떠오르는 알림 토스트 오버레이
struct StreamAlertOverlayView: View {
    let alerts: [StreamAlertItem]
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { alert in
                StreamAlertCard(alert: alert) {
                    onDismiss(alert.id)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }
}

// MARK: - StreamAlertCard

/// 개별 알림 카드 — 후원/구독/공지 타입별 렌더링
private struct StreamAlertCard: View {
    let alert: StreamAlertItem
    let onDismiss: () -> Void

    private var tierColor: Color {
        switch alert.alertType {
        case .donation, .videoDonation, .missionDonation:
            return donationTierColor(amount: alert.donationAmount ?? 0)
        case .subscription:
            return subscriptionTierColor(months: alert.subscriptionMonths ?? 1)
        case .notice:
            return DesignTokens.Colors.accentBlue
        case .systemMessage:
            return DesignTokens.Colors.textSecondary
        }
    }

    private var tierIcon: String {
        switch alert.alertType {
        case .videoDonation:
            return "play.rectangle.fill"
        case .missionDonation:
            return "flag.fill"
        case .donation:
            return donationTierIcon(amount: alert.donationAmount ?? 0)
        case .subscription:
            return subscriptionTierIcon(months: alert.subscriptionMonths ?? 1)
        case .notice:
            return "megaphone.fill"
        case .systemMessage:
            return "info.circle.fill"
        }
    }

    private var typeLabel: String {
        switch alert.alertType {
        case .videoDonation:    return "영상 후원"
        case .missionDonation:  return "미션 후원"
        case .donation:         return donationTierLabel(amount: alert.donationAmount ?? 0)
        case .subscription:     return subscriptionLabel(months: alert.subscriptionMonths ?? 1)
        case .notice:           return "공지"
        case .systemMessage:    return "시스템"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // 아이콘 뱃지
            ZStack {
                Circle()
                    .fill(tierColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: tierIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tierColor)
            }

            // 내용 영역
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.nickname)
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(typeLabel)
                        .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                        .foregroundStyle(tierColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tierColor.opacity(0.15), in: Capsule())
                }

                // 금액 (후원) 또는 개월 (구독)
                if let amount = alert.donationAmount {
                    HStack(spacing: 3) {
                        Text("🪙")
                            .font(.system(size: 14))
                        Text("\(amount.formatted())")
                            .font(DesignTokens.Typography.custom(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(tierColor)
                    }
                }

                // 메시지 내용
                if !alert.content.isEmpty {
                    Text(alert.content)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            // 닫기 버튼
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.black.opacity(0.75))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tierColor.opacity(0.15), tierColor.opacity(0.03)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .strokeBorder(tierColor.opacity(0.3), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        // [GPU 최적화] compositingGroup 제거 + shadow radius 축소 — 오프스크린 렌더 패스 절감
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
    }

    // MARK: - Donation Tier Helpers

    private func donationTierColor(amount: Int) -> Color {
        switch amount {
        case ..<1_000:  return DesignTokens.Colors.accentBlue
        case ..<10_000: return DesignTokens.Colors.chzzkGreen
        case ..<50_000: return DesignTokens.Colors.accentOrange
        default:        return DesignTokens.Colors.error
        }
    }

    private func donationTierIcon(amount: Int) -> String {
        switch amount {
        case ..<1_000:  return "bolt.circle.fill"
        case ..<10_000: return "heart.fill"
        case ..<50_000: return "flame.fill"
        default:        return "crown.fill"
        }
    }

    private func donationTierLabel(amount: Int) -> String {
        switch amount {
        case ..<1_000:  return "소액 후원"
        case ..<10_000: return "후원"
        case ..<50_000: return "큰 후원"
        default:        return "대형 후원"
        }
    }

    // MARK: - Subscription Tier Helpers

    private func subscriptionTierColor(months: Int) -> Color {
        switch months {
        case ..<3:  return DesignTokens.Colors.chzzkGreen
        case ..<6:  return DesignTokens.Colors.accentBlue
        case ..<12: return DesignTokens.Colors.accentPurple
        default:    return DesignTokens.Colors.donation
        }
    }

    private func subscriptionTierIcon(months: Int) -> String {
        switch months {
        case ..<3:  return "star.fill"
        case ..<6:  return "star.circle.fill"
        case ..<12: return "crown"
        default:    return "crown.fill"
        }
    }

    private func subscriptionLabel(months: Int) -> String {
        if months >= 12 && months % 12 == 0 {
            return "\(months / 12)년 구독"
        }
        return "\(months)개월 구독"
    }
}
