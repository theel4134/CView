// MARK: - MultiLiveChildScene.swift
// 자식 인스턴스(--multilive-child) 모드에서 띄우는 단독 채널 윈도우.
// LiveStreamView 를 그대로 재사용하되 다음을 추가합니다:
//   • 부모 PID 워치독 (1초 폴링) — 부모 종료 시 자식도 자동 종료
//   • Distributed Notification IPC — 메인의 quit/setVolume/setMuted 수신
//   • 초기 frame / volume / mute 적용
//   • 창 제목을 채널명으로 설정

import SwiftUI
import AppKit
import CViewCore

struct MultiLiveChildRootView: View {
    let config: MultiLiveChildConfig

    @Environment(AppState.self) private var appState
    @State private var watchdog: ParentProcessWatchdog?
    @State private var ipcObservers: [NSObjectProtocol] = []

    var body: some View {
        LiveStreamView(channelId: config.channelId, isDetachedWindow: false)
            .frame(minWidth: 480, minHeight: 270)
            .onAppear { setupChildInstance() }
            .onDisappear { teardownChildInstance() }
    }

    private func setupChildInstance() {
        // 0) Dock policy: embedded 모드면 삽입 즉시 .accessory 로 전환해 Dock 아이콘 숨김
        if config.hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }

        // 1) 창 frame / 제목 / chrome 적용
        DispatchQueue.main.async {
            if let win = NSApp.windows.first(where: { $0.isVisible }) {
                // borderless: 타이틀바 제거 + 그림자 제거
                if config.borderless {
                    win.styleMask = [.borderless, .resizable]
                    win.isMovableByWindowBackground = false
                    win.hasShadow = false
                    win.titlebarAppearsTransparent = true
                    win.titleVisibility = .hidden
                    win.standardWindowButton(.closeButton)?.isHidden = true
                    win.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    win.standardWindowButton(.zoomButton)?.isHidden = true
                    win.level = .floating
                } else {
                    win.title = "CView – \(config.channelName)"
                }
                if let frame = config.initialFrame {
                    win.setFrame(frame, display: true)
                }
            }
            // Dock 배지는 standalone(=hideFromDock=false) 일 때만 설정
            if !config.hideFromDock {
                let badge = String(config.channelName.prefix(3))
                NSApp.dockTile.badgeLabel = badge
            }
        }

        // 2) 초기 음량/뮤트
        if let pvm = appState.playerViewModel {
            Task { @MainActor in
                pvm.volume = config.initialVolume
                pvm.isMuted = config.startMuted
            }
        }

        // 3) 부모 워치독 시작
        let wd = ParentProcessWatchdog(parentPID: config.parentPID, instanceId: config.instanceId, channelId: config.channelId)
        wd.start()
        watchdog = wd

        // 4) IPC 구독
        let center = DistributedNotificationCenter.default()
        let queue = OperationQueue.main

        let quitObs = center.addObserver(forName: MultiLiveIPC.requestQuit, object: nil, queue: queue) { note in
            guard let id = (note.userInfo?["instanceId"] as? String) ?? (note.object as? String),
                  id == config.instanceId else { return }
            Task { @MainActor in ChildAppExit.terminate(reason: "parent_request") }
        }

        let volObs = center.addObserver(forName: MultiLiveIPC.setVolume, object: nil, queue: queue) { note in
            guard let id = note.userInfo?["instanceId"] as? String, id == config.instanceId,
                  let v = note.userInfo?["volume"] as? Float else { return }
            let vClamped = max(0, min(1, v))
            Task { @MainActor in appState.playerViewModel?.volume = vClamped }
        }

        let muteObs = center.addObserver(forName: MultiLiveIPC.setMuted, object: nil, queue: queue) { note in
            guard let id = note.userInfo?["instanceId"] as? String, id == config.instanceId,
                  let m = note.userInfo?["muted"] as? Bool else { return }
            Task { @MainActor in appState.playerViewModel?.isMuted = m }
        }

        let frameObs = center.addObserver(forName: MultiLiveIPC.setFrame, object: nil, queue: queue) { note in
            guard let id = note.userInfo?["instanceId"] as? String, id == config.instanceId,
                  let x = note.userInfo?["x"] as? Double,
                  let y = note.userInfo?["y"] as? Double,
                  let w = note.userInfo?["w"] as? Double,
                  let h = note.userInfo?["h"] as? Double else { return }
            let frame = CGRect(x: x, y: y, width: w, height: h)
            Task { @MainActor in
                if let win = NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized }) {
                    if win.isMiniaturized { win.deminiaturize(nil) }
                    win.setFrame(frame, display: true, animate: true)
                }
            }
        }

        let minObs = center.addObserver(forName: MultiLiveIPC.setMinimized, object: nil, queue: queue) { note in
            guard let id = note.userInfo?["instanceId"] as? String, id == config.instanceId,
                  let m = note.userInfo?["minimized"] as? Bool else { return }
            Task { @MainActor in
                if let win = NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized }) {
                    if m { win.miniaturize(nil) } else { win.deminiaturize(nil) }
                }
            }
        }

        let chromeObs = center.addObserver(forName: MultiLiveIPC.setChrome, object: nil, queue: queue) { note in
            guard let id = note.userInfo?["instanceId"] as? String, id == config.instanceId else { return }
            let borderless = note.userInfo?["borderless"] as? Bool ?? false
            let hideFromDock = note.userInfo?["hideFromDock"] as? Bool ?? false
            Task { @MainActor in
                _ = NSApp.setActivationPolicy(hideFromDock ? .accessory : .regular)
                if let win = NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized }) {
                    if borderless {
                        win.styleMask = [.borderless, .resizable]
                        win.titleVisibility = .hidden
                        win.titlebarAppearsTransparent = true
                        win.isMovableByWindowBackground = true
                        win.backgroundColor = .black
                        win.standardWindowButton(.closeButton)?.isHidden = true
                        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
                        win.standardWindowButton(.zoomButton)?.isHidden = true
                    } else {
                        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                        win.title = "CView – \(config.channelName)"
                        win.titleVisibility = .visible
                        win.titlebarAppearsTransparent = false
                        win.isMovableByWindowBackground = false
                        win.standardWindowButton(.closeButton)?.isHidden = false
                        win.standardWindowButton(.miniaturizeButton)?.isHidden = false
                        win.standardWindowButton(.zoomButton)?.isHidden = false
                    }
                }
            }
        }

        ipcObservers = [quitObs, volObs, muteObs, frameObs, minObs, chromeObs]

        // 5) 메인에 자식 launch 완료 알림
        center.postNotificationName(
            MultiLiveIPC.childDidLaunch,
            object: config.instanceId,
            userInfo: [
                "instanceId": config.instanceId,
                "channelId": config.channelId,
                "pid": Int(ProcessInfo.processInfo.processIdentifier)
            ],
            deliverImmediately: true
        )
    }

    private func teardownChildInstance() {
        watchdog?.stop()
        watchdog = nil

        let center = DistributedNotificationCenter.default()
        for obs in ipcObservers { center.removeObserver(obs) }
        ipcObservers.removeAll()

        center.postNotificationName(
            MultiLiveIPC.childDidExit,
            object: config.instanceId,
            userInfo: [
                "instanceId": config.instanceId,
                "channelId": config.channelId,
                "reason": "view_disappear"
            ],
            deliverImmediately: true
        )
    }
}

// MARK: - Parent Watchdog

/// 1초마다 부모 PID 의 생존 여부를 검사하고, 부모가 사라지면 자식도 종료합니다.
/// kill(pid, 0) 은 시그널을 보내지 않고 권한/생존만 검사합니다.
@MainActor
final class ParentProcessWatchdog {
    private let parentPID: Int32
    private let instanceId: String
    private let channelId: String
    private var timer: Timer?

    init(parentPID: Int32, instanceId: String, channelId: String) {
        self.parentPID = parentPID
        self.instanceId = instanceId
        self.channelId = channelId
    }

    func start() {
        guard timer == nil else { return }
        // [최적화] 부모 PID 생존 검사 주기: 1s → 2s (자식당 wake-up 50% ↓,
        // 부모 종료 후 자식 cleanup 지연은 ~1→~2s로 사용자 체감 차이 없음)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        // kill(pid, 0): 0 == 살아있음, -1 + errno=ESRCH == 죽음
        let alive = (kill(parentPID, 0) == 0) || (errno == EPERM)
        if !alive {
            ChildAppExit.terminate(reason: "parent_dead")
        }
    }
}

// MARK: - Child Exit Helper

@MainActor
enum ChildAppExit {
    static func terminate(reason: String) {
        let center = DistributedNotificationCenter.default()
        // 자식 종료 알림 (best-effort)
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        center.postNotificationName(
            MultiLiveIPC.childDidExit,
            object: nil,
            userInfo: ["pid": pid, "reason": reason],
            deliverImmediately: true
        )
        // 짧은 grace 후 종료 (notification flush)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.terminate(nil)
        }
    }
}