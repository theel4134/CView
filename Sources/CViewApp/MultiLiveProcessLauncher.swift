// MARK: - MultiLiveProcessLauncher.swift
// 메인 앱이 채널별 자식 CView 인스턴스를 launch / kill / 추적합니다.
//
// macOS 기본 동작은 "동일 .app 번들은 단일 인스턴스" 입니다.
// 동일 번들의 다중 인스턴스를 띄우려면 NSWorkspace.openApplication 의
// `createsNewApplicationInstance = true` 를 사용해야 합니다 (open(1) 의 -n 과 동일).

import Foundation
import AppKit
import Observation
import CViewCore

/// 자식 인스턴스 메타데이터 (메인 측 추적용)
public struct MultiLiveChildInstance: Identifiable, Sendable, Equatable {
    public let id: String          // instanceId
    public let channelId: String
    public let channelName: String
    public var pid: Int32          // 0 == 아직 미확정
    public var launchedAt: Date
    public var initialFrame: CGRect?
}

@MainActor
@Observable
public final class MultiLiveProcessLauncher {
    /// 현재 띄워둔 자식 인스턴스들 (instanceId → meta)
    public private(set) var instances: [String: MultiLiveChildInstance] = [:]

    /// 부모 앱의 멀티라이브 표시 영역(screen 좌표). embedded 모드에서 자식 창을 이 영역에 맞춰 정렬.
    public var embeddedHostFrame: CGRect?

    private var ipcObservers: [NSObjectProtocol] = []

    public init() {
        installIPCObservers()
    }

    deinit {
        // [Bug-fix] IPC 옵저버 해제 — Swift 6 에서 main-actor isolated stored property 는
        // nonisolated deinit 에서 직접 접근 불가 → MainActor.assumeIsolated 로 감싼다.
        MainActor.assumeIsolated {
            let center = DistributedNotificationCenter.default()
            for obs in ipcObservers {
                center.removeObserver(obs)
            }
        }
    }

    // MARK: - Public API

    /// 새 자식 인스턴스를 launch.
    /// - Parameters:
    ///   - channelId: 치지직 채널 ID
    ///   - channelName: 표시명 (창 제목에 사용)
    ///   - initialFrame: 초기 창 frame (옵션)
    ///   - initialVolume: 0.0 - 1.0
    ///   - startMuted: 음소거로 시작
    /// - Returns: 생성된 instanceId. launch 실패 시 nil.
    @discardableResult
    public func launchChild(
        channelId: String,
        channelName: String,
        initialFrame: CGRect? = nil,
        initialVolume: Float = 1.0,
        startMuted: Bool = false,
        borderless: Bool = false,
        hideFromDock: Bool = false
    ) async -> String? {
        // 동일 채널이 이미 떠 있으면 그것을 forefront 로
        if let existing = instances.values.first(where: { $0.channelId == channelId }) {
            activate(instanceId: existing.id)
            return existing.id
        }

        let bundleURL = Bundle.main.bundleURL
        let instanceId = UUID().uuidString
        let parentPID = ProcessInfo.processInfo.processIdentifier

        var args: [String] = [
            "--multilive-child",
            "--channel", channelId,
            "--channel-name", channelName,
            "--parent-pid", String(parentPID),
            "--instance-id", instanceId,
            "--volume", String(format: "%.3f", initialVolume),
            "--muted", startMuted ? "1" : "0",
            "--borderless", borderless ? "1" : "0",
            "--hide-from-dock", hideFromDock ? "1" : "0"
        ]
        if let f = initialFrame {
            args.append(contentsOf: ["--frame", "\(f.origin.x),\(f.origin.y),\(f.size.width),\(f.size.height)"])
        }

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        cfg.arguments = args

        do {
            let app = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: cfg)
            let pid = app.processIdentifier
            instances[instanceId] = MultiLiveChildInstance(
                id: instanceId,
                channelId: channelId,
                channelName: channelName,
                pid: pid,
                launchedAt: Date(),
                initialFrame: initialFrame
            )
            return instanceId
        } catch {
            NSLog("[MultiLiveProcessLauncher] launch 실패: \(error.localizedDescription)")
            return nil
        }
    }

    /// 지정 인스턴스를 종료 요청 (DistributedNotification → 자식이 자체 종료)
    public func terminateChild(instanceId: String) {
        DistributedNotificationCenter.default().postNotificationName(
            MultiLiveIPC.requestQuit,
            object: instanceId,
            userInfo: ["instanceId": instanceId],
            deliverImmediately: true
        )
        // hard fallback: 2초 뒤에도 살아있으면 SIGTERM
        // [최적화] pid 미확정(0)이면 fallback 스케줄 자체를 생략 (불필요한 Task 생성 회피).
        //         detached Task로 옮겨 대량 종료 시 main queue 블록 누적을 방지하고,
        //         kill(pid, 0) probe로 이미 종료된 프로세스에 SIGTERM을 보내지 않도록 함.
        guard let pid = instances[instanceId]?.pid, pid > 0 else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            // kill(pid, 0) == 0 → 프로세스 생존 → SIGTERM 송신
            if kill(pid, 0) == 0 {
                _ = kill(pid, SIGTERM)
            }
        }
    }

    /// 모든 자식 종료 (앱 종료 시 호출)
    public func terminateAll() {
        for id in Array(instances.keys) {
            terminateChild(instanceId: id)
        }
    }

    /// 특정 채널의 자식이 떠 있다면 instanceId 반환
    public func instanceId(forChannel channelId: String) -> String? {
        instances.values.first(where: { $0.channelId == channelId })?.id
    }

    /// 자식 창을 활성화 (forefront)
    public func activate(instanceId: String) {
        guard let pid = instances[instanceId]?.pid, pid > 0,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [])
    }

    /// 음량 변경
    public func setVolume(_ volume: Float, for instanceId: String) {
        DistributedNotificationCenter.default().postNotificationName(
            MultiLiveIPC.setVolume,
            object: instanceId,
            userInfo: ["instanceId": instanceId, "volume": volume],
            deliverImmediately: true
        )
    }

    /// 음소거 변경
    public func setMuted(_ muted: Bool, for instanceId: String) {
        DistributedNotificationCenter.default().postNotificationName(
            MultiLiveIPC.setMuted,
            object: instanceId,
            userInfo: ["instanceId": instanceId, "muted": muted],
            deliverImmediately: true
        )
    }

    /// 자식 창 frame 변경 (자동 그리드/탭 배치)
    public func setFrame(_ frame: CGRect, for instanceId: String) {
        DistributedNotificationCenter.default().postNotificationName(
            MultiLiveIPC.setFrame,
            object: instanceId,
            userInfo: [
                "instanceId": instanceId,
                "x": Double(frame.origin.x),
                "y": Double(frame.origin.y),
                "w": Double(frame.size.width),
                "h": Double(frame.size.height)
            ],
            deliverImmediately: true
        )
    }

    /// 자식 창 minimize / restore
    public func setMinimized(_ minimized: Bool, for instanceId: String) {
        DistributedNotificationCenter.default().postNotificationName(
            MultiLiveIPC.setMinimized,
            object: instanceId,
            userInfo: ["instanceId": instanceId, "minimized": minimized],
            deliverImmediately: true
        )
    }

    /// 자식 창 스타일 변경 (별도 앱 / 부모 앱 내 표시)
    public func setChrome(borderless: Bool, hideFromDock: Bool, for instanceId: String) {
        DistributedNotificationCenter.default().postNotificationName(
            MultiLiveIPC.setChrome,
            object: instanceId,
            userInfo: [
                "instanceId": instanceId,
                "borderless": borderless,
                "hideFromDock": hideFromDock
            ],
            deliverImmediately: true
        )
    }

    // MARK: - Auto Layout

    /// 모든 자식 창을 지정 layout + presentation 모드로 자동 정렬.
    public func applyLayout(
        mode: MultiLiveProcessLayoutMode,
        selectedInstanceId: String? = nil,
        screen: NSScreen? = nil,
        presentation: MultiLiveProcessPresentation = .standalone
    ) {
        let active = instances.values.sorted { $0.launchedAt < $1.launchedAt }
        guard !active.isEmpty else { return }

        let isEmbedded = presentation == .embedded
        for inst in active {
            setChrome(borderless: isEmbedded, hideFromDock: isEmbedded, for: inst.id)
        }

        guard let area = targetArea(for: presentation, screen: screen) else { return }

        switch mode {
        case .free:
            // 부모 앱 내 표시 모드에서는 자유 배치도 host 영역 안에서 cascade 배치로 시작
            guard isEmbedded else { return }
            let frames = cascadeFrames(in: area, count: active.count)
            for (inst, frame) in zip(active, frames) {
                setMinimized(false, for: inst.id)
                setFrame(frame, for: inst.id)
            }

        case .grid:
            let frames = gridFrames(in: area, count: active.count)
            for (inst, frame) in zip(active, frames) {
                setMinimized(false, for: inst.id)
                setFrame(frame, for: inst.id)
            }

        case .tab:
            let selectedId = selectedInstanceId ?? active.first?.id
            for inst in active {
                if inst.id == selectedId {
                    setMinimized(false, for: inst.id)
                    setFrame(area, for: inst.id)
                } else {
                    setMinimized(true, for: inst.id)
                }
            }
        }
    }

    private func targetArea(for presentation: MultiLiveProcessPresentation, screen: NSScreen?) -> CGRect? {
        switch presentation {
        case .standalone:
            let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
            return targetScreen?.visibleFrame

        case .embedded:
            if let embeddedHostFrame, !embeddedHostFrame.isEmpty {
                return embeddedHostFrame.insetBy(dx: 2, dy: 2)
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow,
               let contentView = window.contentView {
                let contentRect = window.convertToScreen(contentView.bounds)
                let inset: CGFloat = 10
                return CGRect(
                    x: contentRect.minX + inset,
                    y: contentRect.minY + inset,
                    width: max(320, contentRect.width - inset * 2),
                    height: max(220, contentRect.height - 110)
                )
            }
            let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
            return targetScreen?.visibleFrame.insetBy(dx: 80, dy: 80)
        }
    }

    /// 그리드 레이아웃 계산 — N개 패인을 area 안에 균등 배치
    private func gridFrames(in area: CGRect, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let cols: Int
        let rows: Int
        switch count {
        case 1: cols = 1; rows = 1
        case 2: cols = 2; rows = 1
        case 3, 4: cols = 2; rows = 2
        case 5, 6: cols = 3; rows = 2
        case 7, 8, 9: cols = 3; rows = 3
        default:
            let c = Int(ceil(sqrt(Double(count))))
            cols = c
            rows = Int(ceil(Double(count) / Double(c)))
        }

        let gap: CGFloat = 4
        let cellW = (area.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (area.height - gap * CGFloat(rows + 1)) / CGFloat(rows)

        var frames: [CGRect] = []
        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            let x = area.minX + gap + CGFloat(col) * (cellW + gap)
            let y = area.maxY - gap - CGFloat(row + 1) * cellH - CGFloat(row) * gap
            frames.append(CGRect(x: x, y: y, width: cellW, height: cellH))
        }
        return frames
    }

    /// 자유 배치용 cascade frame 계산 — 부모 앱 내 모드에서 겹치지 않게 살짝 오프셋
    private func cascadeFrames(in area: CGRect, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let baseW = max(480, min(area.width * 0.72, area.width))
        let baseH = max(270, min(area.height * 0.72, area.height))
        let step: CGFloat = 28
        var frames: [CGRect] = []
        for i in 0..<count {
            let x = min(area.minX + CGFloat(i) * step, max(area.minX, area.maxX - baseW))
            let y = min(area.minY + CGFloat(i) * step, max(area.minY, area.maxY - baseH))
            frames.append(CGRect(x: x, y: y, width: baseW, height: baseH))
        }
        return frames
    }

    /// 신규 자식 launch 시 사용할 초기 frame 계산 (현재 layout + presentation 모드 기준)
    public func suggestedInitialFrame(
        for newIndex: Int,
        totalAfterLaunch: Int,
        mode: MultiLiveProcessLayoutMode,
        presentation: MultiLiveProcessPresentation = .standalone,
        screen: NSScreen? = nil
    ) -> CGRect? {
        guard let area = targetArea(for: presentation, screen: screen) else { return nil }
        if mode == .tab {
            return area
        }
        if mode == .free {
            guard presentation == .embedded else { return nil }
            let frames = cascadeFrames(in: area, count: totalAfterLaunch)
            return frames.indices.contains(newIndex) ? frames[newIndex] : nil
        }
        let frames = gridFrames(in: area, count: totalAfterLaunch)
        return frames.indices.contains(newIndex) ? frames[newIndex] : nil
    }

    // MARK: - IPC observers (자식 종료 추적)

    private func installIPCObservers() {
        let center = DistributedNotificationCenter.default()
        let queue = OperationQueue.main

        let launchObs = center.addObserver(forName: MultiLiveIPC.childDidLaunch, object: nil, queue: queue) { [weak self] note in
            guard let self,
                  let id = note.userInfo?["instanceId"] as? String else { return }
            let pid = note.userInfo?["pid"] as? Int
            Task { @MainActor in
                if var inst = self.instances[id], let pid {
                    inst.pid = Int32(pid)
                    self.instances[id] = inst
                }
            }
        }

        let exitObs = center.addObserver(forName: MultiLiveIPC.childDidExit, object: nil, queue: queue) { [weak self] note in
            guard let self,
                  let id = note.userInfo?["instanceId"] as? String else { return }
            Task { @MainActor in
                self.instances.removeValue(forKey: id)
            }
        }

        ipcObservers = [launchObs, exitObs]
    }
}
