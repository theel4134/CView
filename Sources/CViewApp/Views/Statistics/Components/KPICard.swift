// MARK: - Statistics/Components/KPICard.swift
// 통계 화면 공용 KPI 카드 — 기존 StatCard 확장 버전 (서브라벨/상태칩/sparkline 옵션)

import SwiftUI
import Charts
import CViewCore
import CViewUI

/// 데이터 대시보드형 KPI 카드.
/// - title: 작은 라벨
/// - value: 메인 값 (monospaced)
/// - subValue: 보조 라벨 (예: 단위, 변화 추세)
/// - icon: SF Symbol
/// - color: 강조 색
/// - sparkline: nil 이면 미표시, 있으면 카드 하단에 작은 line chart 렌더
struct KPICard: View {
    let title: String
    let value: String
    var subValue: String? = nil
    let icon: String
    let color: Color
    var sparkline: [Double]? = nil
    var status: Status? = nil

    @State private var isHovered = false

    enum Status {
        case good, warning, critical
        var color: Color {
            switch self {
            case .good: return DesignTokens.Colors.chzzkGreen
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(DesignTokens.Typography.custom(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer(minLength: 0)
                if let status {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(DesignTokens.Typography.custom(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let subValue {
                    Text(subValue)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            if let sparkline, sparkline.count >= 2 {
                sparklineChart(sparkline)
                    .frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isHovered ? color.opacity(0.4) : DesignTokens.Glass.borderColor,
                    lineWidth: isHovered ? 1 : 0.5
                )
        }
        .animation(DesignTokens.Animation.smooth, value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private func sparklineChart(_ values: [Double]) -> some View {
        Chart(Array(values.enumerated()), id: \.offset) { idx, v in
            AreaMark(x: .value("i", idx), y: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.35), color.opacity(0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("i", idx), y: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(Color.clear) }
    }
}
