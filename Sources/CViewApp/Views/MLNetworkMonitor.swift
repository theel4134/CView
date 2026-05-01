// MARK: - MLNetworkMonitor.swift
// 네트워크 모니터 — 히스토리 링버퍼 + 스파크라인 + 전체 합산 탭
//
// 2026-04-30 집계 안정화 작업 중 추가:
// - VLCPlayerEngine 통계가 10–15s 간격이라 첫 표시 지연이 길고 stall 시 0 으로 굳어
//   보이는 문제가 있었다. 이 파일은 VLC 통계와 별개로 LocalStreamProxy 가 제공하는
//   누적 바이트 스냅샷을 짧은 주기로 폴링해 "최근 2s 평균 대역폭" 을 계산하고,
//   세션 별 60-샘플 링버퍼를 유지한다.
// - MLNetworkAggregateTab 는 현재 멀티라이브 모든 세션의 합/평균을 한 화면에 노출한다.

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - 히스토리 링버퍼

/// 네트워크 모니터용 60-샘플 링버퍼.
/// 2초 폴링 기준 2분 분량을 유지한다 — 짧은 추세 그래프와 합산 통계에 사용.
@Observable
@MainActor
final class NetworkMonitorHistory {

    struct Sample: Sendable {
        let timestamp: Date
        /// 표시용 대역폭 (bytes/sec) — proxy 우선, fallback VLC.
        let bandwidthBytesPerSec: Double
        /// FPS — 엔진별 메트릭에서 가져온 그대로 (0 = 미측정)
        let fps: Double
        /// 0…1
        let healthScore: Double
        /// 0…1
        let bufferHealth: Double
        /// 누적 드롭 프레임 (구간 단위)
        let dropsDelta: Int
        /// 누적 지연 프레임 (구간 단위)
        let lateDelta: Int
    }

    static let capacity: Int = 60

    private(set) var samples: [Sample] = []

    func append(_ sample: Sample) {
        samples.append(sample)
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    func clear() { samples.removeAll(keepingCapacity: true) }

    // MARK: - 분석 헬퍼

    /// 최근 N 초 평균 대역폭 (Bytes/sec) — 폴링 간격이 일정치 않으니 단순 평균.
    func avgBandwidth(lastSeconds: TimeInterval = 30) -> Double {
        let cutoff = Date().addingTimeInterval(-lastSeconds)
        let recent = samples.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.bandwidthBytesPerSec).reduce(0, +) / Double(recent.count)
    }

    func peakBandwidth(lastSeconds: TimeInterval = 30) -> Double {
        let cutoff = Date().addingTimeInterval(-lastSeconds)
        return samples.filter { $0.timestamp >= cutoff }.map(\.bandwidthBytesPerSec).max() ?? 0
    }

    /// CSV 내보내기 — 헤더 포함, 시간/대역폭(kbps)/FPS/health/buffer/drops/late.
    func csvDump() -> String {
        var lines = ["timestamp,bandwidth_kbps,fps,health,buffer,drops,late"]
        let fmt = ISO8601DateFormatter()
        for s in samples {
            let kbps = s.bandwidthBytesPerSec * 8.0 / 1000.0
            lines.append("\(fmt.string(from: s.timestamp)),\(String(format: "%.1f", kbps)),\(String(format: "%.1f", s.fps)),\(String(format: "%.3f", s.healthScore)),\(String(format: "%.3f", s.bufferHealth)),\(s.dropsDelta),\(s.lateDelta)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 스파크라인

/// 가벼운 sparkline — Path 1개로 그려서 60샘플 × 다중 세션에서도 GPU 부하 거의 없음.
struct NetworkSparkline: View {
    let values: [Double]
    let tint: Color
    /// 0 으로 떨어지는 경우도 baseline 으로 표시하기 위해 명시적 max 지정 가능.
    let displayMax: Double?

    init(values: [Double], tint: Color = .green, displayMax: Double? = nil) {
        self.values = values
        self.tint = tint
        self.displayMax = displayMax
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottomLeading) {
                tint.opacity(0.08)
                if values.count >= 2 {
                    let normalised = normalise(values, geoMax: displayMax)
                    Path { path in
                        let stepX = w / CGFloat(max(values.count - 1, 1))
                        for (i, v) in normalised.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = h - CGFloat(v) * h
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func normalise(_ values: [Double], geoMax: Double?) -> [Double] {
        let maxV = max(geoMax ?? (values.max() ?? 1), 0.0001)
        return values.map { max(0, min(1, $0 / maxV)) }
    }
}

// MARK: - 합계 통계

struct MLNetworkAggregateSnapshot {
    let activeSessions: Int
    let totalBandwidthBytesPerSec: Double
    let avgHealthScore: Double
    let avgBufferHealth: Double
    let totalRequests: Int
    let totalCacheHits: Int
    let totalCacheMisses: Int
    let totalErrors: Int
    let total403: Int
    let totalBytesReceived: Int64
    let totalBytesServed: Int64
    let activeConnections: Int
    let totalDropsDelta: Int
    let totalLateDelta: Int
    /// 세션 별 요약 행 (UI 카드용)
    let perSession: [SessionSummaryRow]

    struct SessionSummaryRow: Identifiable {
        let id: UUID
        let channelName: String
        let healthScore: Double
        let bandwidthBytesPerSec: Double
        let fps: Double
        let engine: String
        let resolution: String?
        let warningCount: Int
    }

    static let empty = MLNetworkAggregateSnapshot(
        activeSessions: 0, totalBandwidthBytesPerSec: 0, avgHealthScore: 0,
        avgBufferHealth: 0, totalRequests: 0, totalCacheHits: 0, totalCacheMisses: 0,
        totalErrors: 0, total403: 0, totalBytesReceived: 0, totalBytesServed: 0,
        activeConnections: 0, totalDropsDelta: 0, totalLateDelta: 0, perSession: [])

    var cacheHitRatio: Double {
        let t = totalCacheHits + totalCacheMisses
        return t > 0 ? Double(totalCacheHits) / Double(t) : 0
    }
}

// MARK: - 합계 탭

struct MLNetworkAggregateTab: View {
    let sessions: [MultiLiveSession]

    private var snapshot: MLNetworkAggregateSnapshot { Self.aggregate(sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            summarySection
            Divider()
            perSessionSection
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("전체 합산 — 활성 세션 \(snapshot.activeSessions)개")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Spacer()
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(healthColor(snapshot.avgHealthScore))
                    .frame(width: 10, height: 10)
                Text("평균 스트림 건강도")
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.0f%%", snapshot.avgHealthScore * 100))
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(healthColor(snapshot.avgHealthScore))
            }
            ProgressView(value: snapshot.avgHealthScore)
                .tint(healthColor(snapshot.avgHealthScore))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.xs) {
                aggregateCard("총 대역폭", formatBitrate(snapshot.totalBandwidthBytesPerSec), icon: "arrow.down.circle")
                aggregateCard("평균 버퍼 건강도", String(format: "%.0f%%", snapshot.avgBufferHealth * 100), icon: "heart.fill")
                aggregateCard("총 요청", "\(snapshot.totalRequests)", icon: "arrow.up.arrow.down")
                aggregateCard("캐시 적중률", String(format: "%.0f%%", snapshot.cacheHitRatio * 100), icon: "memorychip")
                aggregateCard("활성 연결", "\(snapshot.activeConnections)", icon: "link")
                aggregateCard("드롭/지연", "\(snapshot.totalDropsDelta)/\(snapshot.totalLateDelta)",
                              icon: "exclamationmark.triangle",
                              alert: (snapshot.totalDropsDelta + snapshot.totalLateDelta) > 0)
            }

            HStack {
                Label("수신: \(formatBytes(snapshot.totalBytesReceived))", systemImage: "arrow.down.doc")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Label("전달: \(formatBytes(snapshot.totalBytesServed))", systemImage: "arrow.up.doc")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            if snapshot.totalErrors > 0 || snapshot.total403 > 0 {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if snapshot.totalErrors > 0 {
                        Label("에러 \(snapshot.totalErrors)", systemImage: "exclamationmark.triangle.fill")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.warning)
                    }
                    if snapshot.total403 > 0 {
                        Label("연속 403: \(snapshot.total403)", systemImage: "lock.slash")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.warning)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var perSessionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                Text("세션별 요약")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Spacer()
            }

            if snapshot.perSession.isEmpty {
                Text("활성 세션이 없습니다.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                ForEach(snapshot.perSession) { row in
                    sessionRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ row: MLNetworkAggregateSnapshot.SessionSummaryRow) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(healthColor(row.healthScore))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.channelName)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(row.engine)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DesignTokens.Colors.surfaceElevated))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                HStack(spacing: 8) {
                    Text(String(format: "%.0f%%", row.healthScore * 100))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(healthColor(row.healthScore))
                    Text(formatBitrate(row.bandwidthBytesPerSec))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(String(format: "%.1f fps", row.fps))
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    if let res = row.resolution {
                        Text(res)
                            .font(DesignTokens.Typography.custom(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            Spacer()
            if row.warningCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("\(row.warningCount)")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                }
                .foregroundStyle(DesignTokens.Colors.warning)
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }

    @ViewBuilder
    private func aggregateCard(_ label: String, _ value: String, icon: String, alert: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(alert ? DesignTokens.Colors.warning : DesignTokens.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(alert ? DesignTokens.Colors.warning : DesignTokens.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(alert ? DesignTokens.Colors.warning.opacity(0.06) : DesignTokens.Colors.surfaceElevated.opacity(0.5))
        )
    }

    private func healthColor(_ score: Double) -> Color {
        if score > 0.8 { return .green }
        if score > 0.5 { return .orange }
        return .red
    }

    private func formatBitrate(_ bytesPerSec: Double) -> String {
        let mbps = bytesPerSec * 8.0 / 1_000_000.0
        if mbps >= 1.0 { return String(format: "%.1f Mbps", mbps) }
        let kbps = bytesPerSec * 8.0 / 1_000.0
        return String(format: "%.0f kbps", kbps)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }

    // MARK: - 합산 계산기

    static func aggregate(_ sessions: [MultiLiveSession]) -> MLNetworkAggregateSnapshot {
        guard !sessions.isEmpty else { return .empty }
        var rows: [MLNetworkAggregateSnapshot.SessionSummaryRow] = []
        var totalBandwidth: Double = 0
        var healthSum: Double = 0
        var bufferSum: Double = 0
        var measuredCount: Int = 0
        var totalRequests = 0, hits = 0, misses = 0, errors = 0, c403 = 0
        var bytesRcv: Int64 = 0, bytesSrv: Int64 = 0
        var connections = 0
        var dropsDelta = 0, lateDelta = 0

        for s in sessions {
            let bw = s.displayBandwidthBytesPerSec
            let (health, fps, buf, engine, resolution, warnings, drops, late) = sessionMetricSummary(s)

            totalBandwidth += bw
            if health > 0 {
                healthSum += health
                bufferSum += buf
                measuredCount += 1
            }
            dropsDelta += drops
            lateDelta += late

            if let p = s.latestProxyStats {
                totalRequests += p.totalRequests
                hits += p.cacheHits
                misses += p.cacheMisses
                errors += p.errorCount
                c403 += p.consecutive403Count
                bytesRcv += p.totalBytesReceived
                bytesSrv += p.totalBytesServed
                connections += p.activeConnections
            }

            // 활성 세션만 행에 포함 (재생 중)
            if case .playing = s.loadState {
                rows.append(.init(
                    id: s.id,
                    channelName: s.channelName.isEmpty ? s.channelId : s.channelName,
                    healthScore: health,
                    bandwidthBytesPerSec: bw,
                    fps: fps,
                    engine: engine,
                    resolution: resolution,
                    warningCount: warnings
                ))
            }
        }

        let avgHealth = measuredCount > 0 ? healthSum / Double(measuredCount) : 0
        let avgBuffer = measuredCount > 0 ? bufferSum / Double(measuredCount) : 0
        return MLNetworkAggregateSnapshot(
            activeSessions: rows.count,
            totalBandwidthBytesPerSec: totalBandwidth,
            avgHealthScore: avgHealth,
            avgBufferHealth: avgBuffer,
            totalRequests: totalRequests,
            totalCacheHits: hits,
            totalCacheMisses: misses,
            totalErrors: errors,
            total403: c403,
            totalBytesReceived: bytesRcv,
            totalBytesServed: bytesSrv,
            activeConnections: connections,
            totalDropsDelta: dropsDelta,
            totalLateDelta: lateDelta,
            perSession: rows)
    }

    /// 세션 한 건의 핵심 지표 요약 — 엔진(VLC/AV/HLS) 별로 다른 메트릭을 통일된 튜플로 정규화.
    private static func sessionMetricSummary(
        _ s: MultiLiveSession
    ) -> (health: Double, fps: Double, buffer: Double, engine: String,
          resolution: String?, warnings: Int, drops: Int, late: Int) {
        if let m = s.latestMetrics {
            let warn = (m.droppedFramesDelta > 0 ? 1 : 0)
                + (m.latePicturesDelta > 0 ? 1 : 0)
                + (m.lostAudioBuffersDelta > 0 ? 1 : 0)
                + (m.demuxCorruptedDelta > 0 ? 1 : 0)
            return (m.healthScore, m.fps, m.bufferHealth, "VLC", m.resolution, warn,
                    m.droppedFramesDelta, m.latePicturesDelta)
        }
        if let m = s.latestAVMetrics {
            let warn = (m.droppedFramesDelta > 0 ? 1 : 0)
            return (m.healthScore, 0, m.bufferHealth, "AVPlayer", m.resolution, warn,
                    m.droppedFramesDelta, 0)
        }
        if let m = s.latestHLSJSMetrics {
            let warn = (m.droppedFramesDelta > 0 ? 1 : 0)
            return (m.healthScore, m.fps, m.bufferHealth, "HLS.js", m.resolution, warn,
                    m.droppedFramesDelta, 0)
        }
        return (0, 0, 0, "—", nil, 0, 0, 0)
    }
}
