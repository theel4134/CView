// MARK: - PerformanceOverlayView.swift
// CViewApp - 실시간 성능 메트릭 오버레이
// Metal 3: Canvas 기반 단일 GPU 드로우 패스 — 9개 row × HStack 레이아웃 제거
// FPS, 메모리, GPU, 네트워크, 버퍼 상태, 레이턴시 표시

import SwiftUI
import CViewCore
import CViewMonitoring

struct PerformanceOverlayView: View {
    
    let monitor: PerformanceMonitor
    
    @State private var currentMetrics: PerformanceMonitor.Metrics?
    @State private var metricsTask: Task<Void, Never>?

    // 사전 계산된 메트릭 행 — Canvas 드로잉용
    private struct MetricLine {
        let label: String
        let value: String
        let color: Color
    }

    private var metricLines: [MetricLine] {
        guard let m = currentMetrics else {
            return [MetricLine(label: "", value: "수집 중...", color: .green.opacity(0.6))]
        }
        return [
            MetricLine(label: "FPS",  value: String(format: "%.1f",     m.fps),                  color: fpsColor(m.fps)),
            MetricLine(label: "CPU",  value: String(format: "%.0f%%",   m.cpuUsage),             color: cpuColor(m.cpuUsage)),
            MetricLine(label: "MEM",  value: String(format: "%.0f MB",  m.memoryUsageMB),        color: memColor(m.memoryUsageMB)),
            MetricLine(label: "GPU",  value: String(format: "%.0f%%",   m.gpuUsagePercent),      color: gpuColor(m.gpuUsagePercent)),
            MetricLine(label: "RNDR", value: String(format: "%.0f%%",   m.gpuRendererPercent),   color: gpuColor(m.gpuRendererPercent)),
            MetricLine(label: "GMEM", value: String(format: "%.0f MB",  m.gpuMemoryUsedMB),      color: gpuMemColor(m.gpuMemoryUsedMB)),
            MetricLine(label: "NET",  value: formatBytes(m.networkBytesReceived),                 color: .cyan),
            MetricLine(label: "BUF",  value: String(format: "%.0f%%",   m.bufferHealthPercent),  color: bufferColor(m.bufferHealthPercent)),
            MetricLine(label: "LAT",  value: String(format: "%.0f ms",  m.latencyMs),            color: latencyColor(m.latencyMs)),
            MetricLine(label: "DROP", value: "\(m.droppedFrames)",                                color: m.droppedFrames > 0 ? .red : .green),
        ]
    }

    // Canvas 고정 레이아웃 상수
    private let rowHeight: CGFloat = 15
    private let headerHeight: CGFloat = 28   // DEBUG 레이블 + 구분선
    private let labelWidth: CGFloat  = 34
    private let canvasWidth: CGFloat = 124
    private let padding: CGFloat     = 8

    var body: some View {
        // Metal 3: Canvas — SwiftUI 레이아웃 엔진 우회, 단일 Metal 드로우 패스
        Canvas { context, size in
            // ── DEBUG 헤더 ────────────────────────────────────────
            context.draw(
                Text("DEBUG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green),
                at: CGPoint(x: 0, y: 0),
                anchor: .topLeading
            )

            // 구분선
            var linePath = Path()
            linePath.move(to: CGPoint(x: 0, y: 16))
            linePath.addLine(to: CGPoint(x: size.width, y: 16))
            context.stroke(linePath, with: .color(.green.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 0.5))

            // ── 메트릭 행 ─────────────────────────────────────────
            for (i, line) in metricLines.enumerated() {
                let y = headerHeight + CGFloat(i) * rowHeight

                // 레이블 (고정 폭, 연한 초록)
                if !line.label.isEmpty {
                    context.draw(
                        Text(line.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.7)),
                        at: CGPoint(x: 0, y: y),
                        anchor: .topLeading
                    )
                }

                // 값 (색상별)
                context.draw(
                    Text(line.value)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(line.color),
                    at: CGPoint(x: line.label.isEmpty ? 0 : labelWidth + 4, y: y),
                    anchor: .topLeading
                )
            }
        }
        .frame(
            width:  canvasWidth,
            height: headerHeight + CGFloat(metricLines.count) * rowHeight
        )
        .padding(padding)
        .background(.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        }
        .drawingGroup(opaque: false)  // 오버레이 전체 단일 Metal 텍스처
        .onAppear { startListening() }
        .onDisappear { metricsTask?.cancel() }
    }
    
    // MARK: - Colors
    
    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 55 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }

    private func cpuColor(_ percent: Double) -> Color {
        if percent < 40  { return .green }
        if percent < 80  { return .yellow }
        return .red
    }
    
    private func memColor(_ mb: Double) -> Color {
        if mb < 200 { return .green }
        if mb < 500 { return .yellow }
        return .red
    }
    
    private func bufferColor(_ percent: Double) -> Color {
        if percent >= 80 { return .green }
        if percent >= 40 { return .yellow }
        return .red
    }
    
    private func latencyColor(_ ms: Double) -> Color {
        if ms < 2000 { return .green }
        if ms < 5000 { return .yellow }
        return .red
    }
    
    private func gpuColor(_ percent: Double) -> Color {
        if percent < 50 { return .green }
        if percent < 80 { return .yellow }
        return .red
    }
    
    private func gpuMemColor(_ mb: Double) -> Color {
        if mb < 2048 { return .green }
        if mb < 4096 { return .yellow }
        return .red
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
    
    // MARK: - Listening
    
    private func startListening() {
        metricsTask?.cancel()
        metricsTask = Task {
            let stream = await monitor.metrics()
            for await metrics in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.currentMetrics = metrics
                }
            }
        }
    }
}
