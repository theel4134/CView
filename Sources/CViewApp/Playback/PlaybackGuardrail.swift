// [Plan 2026-04-30 PLY-2, PLY-1]
import Foundation
import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Severity
enum GuardrailSeverity: String, Codable, Sendable, Comparable {
    case info, warning, critical
    private var order: Int {
        switch self {
        case .info:     0
        case .warning:  1
        case .critical: 2
        }
    }
    static func < (l: Self, r: Self) -> Bool { l.order < r.order }
}

// MARK: - GuardrailEvent
struct GuardrailEvent: Codable, Identifiable, Sendable {
    enum Kind: String, Codable {
        case latencyModeChanged
        case abrDowngrade
        case abrRecovery
        case stall
        case proxyTTFBHigh
        case wsFallback
        case engineSwitch
    }
    var id: UUID = .init()
    var channelId: String
    var kind: Kind
    var severity: GuardrailSeverity
    var message: String
    var metrics: [String: Double] = [:]
    var createdAt: Date = .init()
}

// MARK: - GuardrailEventLog (ring buffer, max 200 events, actor-isolated)
@MainActor
final class GuardrailEventLog: ObservableObject {
    static let shared = GuardrailEventLog()
    private(set) var events: [GuardrailEvent] = []
    private let capacity = 200

    func append(_ event: GuardrailEvent) {
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    func events(for channelId: String) -> [GuardrailEvent] {
        events.filter { $0.channelId == channelId }
    }

    func latestEvent(for channelId: String) -> GuardrailEvent? {
        events.last(where: { $0.channelId == channelId })
    }

    func clear(channelId: String) {
        events.removeAll { $0.channelId == channelId }
    }
}

// MARK: - PlaybackGuardrailChipsView
/// LiveStreamView 상단에 표시되는 5개 compact chip 행 (Latency / Buffer / Quality / Proxy / Engine)
struct PlaybackGuardrailChipsView: View {
    let playerVM: PlayerViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                latencyChip
                bufferChip
                qualityChip
                proxyChip
                engineChip
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 4)
        }
        .frame(height: 28)
    }

    // MARK: Latency
    private var latencyChip: some View {
        let info = playerVM.latencyInfo
        let value = info.map { String(format: "%.1fs", $0.current) } ?? "--"
        let isGood = info.map { $0.current <= $0.target * 1.5 } ?? true
        return GuardrailChip(
            icon: "clock.fill",
            label: value,
            tint: isGood ? .secondary : DesignTokens.Colors.warning,
            tooltip: info.map { "현재: \(String(format:"%.2f", $0.current))s  목표: \(String(format:"%.2f", $0.target))s  EWMA: \(String(format:"%.2f", $0.ewma))s" } ?? "지연 정보 없음"
        )
    }

    // MARK: Buffer
    private var bufferChip: some View {
        let bh = playerVM.bufferHealth
        let value = bh.map { String(format: "%.1fs", $0.currentLevel) } ?? "--"
        let isHealthy = bh?.isHealthy ?? true
        return GuardrailChip(
            icon: "waveform.path",
            label: value,
            tint: isHealthy ? .secondary : DesignTokens.Colors.warning,
            tooltip: bh.map { "버퍼: \(String(format:"%.1f", $0.currentLevel))s / 목표 \(String(format:"%.1f", $0.targetLevel))s  신뢰도: \(Int($0.confidence * 100))%" } ?? "버퍼 정보 없음"
        )
    }

    // MARK: Quality
    private var qualityChip: some View {
        let quality = playerVM.currentQuality?.name ?? "auto"
        return GuardrailChip(
            icon: "sparkles",
            label: quality,
            tint: .secondary,
            tooltip: "현재 화질: \(quality)"
        )
    }

    // MARK: Proxy
    private var proxyChip: some View {
        let mode = playerVM.currentProxyMode
        let isNone = mode == "none"
        return GuardrailChip(
            icon: "network",
            label: isNone ? "직접" : "프록시",
            tint: isNone ? DesignTokens.Colors.warning : .secondary,
            tooltip: mode
        )
    }

    // MARK: Engine
    private var engineChip: some View {
        let engine = playerVM.currentEngineType
        let label: String = switch engine {
        case .avPlayer: "AVPlayer"
        case .vlc:      "VLC"
        case .hlsjs:    "HLS.js"
        @unknown default: "?"
        }
        let icon: String = switch engine {
        case .avPlayer: "play.circle"
        case .vlc:      "play.square.stack"
        case .hlsjs:    "globe"
        @unknown default: "questionmark.circle"
        }
        return GuardrailChip(icon: icon, label: label, tint: .secondary, tooltip: "재생 엔진: \(label)")
    }
}

// MARK: - GuardrailChip
private struct GuardrailChip: View {
    let icon: String
    let label: String
    let tint: Color
    let tooltip: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(isHovered ? DesignTokens.Colors.textPrimary : tint.opacity(0.85))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(isHovered
                      ? DesignTokens.Colors.surfaceElevated.opacity(0.9)
                      : DesignTokens.Colors.surfaceBase.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .strokeBorder(DesignTokens.Colors.border.opacity(0.4), lineWidth: 0.5)
                }
        }
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityElement(children: .ignore)
        .animation(DesignTokens.Animation.micro, value: isHovered)
    }
}
