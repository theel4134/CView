// MARK: - AppLaunchMode.swift
// CommandLine 인자를 파싱해 메인/자식 모드를 결정합니다.
//
// 멀티라이브 "프로세스 격리" 모드에서는 각 채널을 별도 CView 인스턴스로 띄우는데,
// 자식 인스턴스는 다음 인자를 받습니다:
//   --multilive-child --channel <channelId> --channel-name <name> --parent-pid <pid>
//   [--frame x,y,w,h] [--volume 0.5] [--audio-only]
//
// 자식 모드에서는 메인 UI/그리드/메뉴를 모두 숨기고 단일 채널 LiveStreamView 만 띄웁니다.

import Foundation
import CoreGraphics

/// 앱 실행 모드
public enum AppLaunchMode: Sendable, Equatable {
    /// 일반 메인 앱 (그리드 / 사이드바 / 채팅 등 전체 UI)
    case main
    /// 멀티라이브 자식 인스턴스 (단일 채널 단독 창)
    case multiLiveChild(MultiLiveChildConfig)

    public var isChild: Bool {
        if case .multiLiveChild = self { return true }
        return false
    }

    public var childConfig: MultiLiveChildConfig? {
        if case .multiLiveChild(let cfg) = self { return cfg }
        return nil
    }
}

/// 자식 인스턴스 launch 시 전달되는 설정
public struct MultiLiveChildConfig: Sendable, Equatable, Codable {
    /// 채널 ID (필수)
    public let channelId: String
    /// 채널 표시명 (창 제목 / 워치독 로그용)
    public let channelName: String
    /// 부모 프로세스 PID (워치독: 부모 종료 시 자식도 자동 종료)
    public let parentPID: Int32
    /// 자식 인스턴스 식별자 (메인 ↔ 자식 IPC 키)
    public let instanceId: String
    /// 초기 창 frame (x, y, width, height) — Cocoa 좌표(좌하단 원점)
    public let initialFrame: CGRect?
    /// 초기 음량 (0.0 - 1.0)
    public let initialVolume: Float
    /// 음소거로 시작
    public let startMuted: Bool
    /// 자식 창을 보더레스(embedded) 로 시작
    public let borderless: Bool
    /// Dock 아이콘을 숨긴 상태(.accessory) 로 시작
    public let hideFromDock: Bool

    public init(
        channelId: String,
        channelName: String,
        parentPID: Int32,
        instanceId: String,
        initialFrame: CGRect? = nil,
        initialVolume: Float = 1.0,
        startMuted: Bool = false,
        borderless: Bool = false,
        hideFromDock: Bool = false
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.parentPID = parentPID
        self.instanceId = instanceId
        self.initialFrame = initialFrame
        self.initialVolume = initialVolume
        self.startMuted = startMuted
        self.borderless = borderless
        self.hideFromDock = hideFromDock
    }
}

// MARK: - Parser

public enum AppLaunchModeParser {
    /// 현재 프로세스 인자에서 모드를 결정
    public static func detect() -> AppLaunchMode {
        return parse(arguments: CommandLine.arguments)
    }

    /// 임의 인자 배열에서 모드를 결정 (테스트용)
    public static func parse(arguments: [String]) -> AppLaunchMode {
        guard arguments.contains("--multilive-child") else { return .main }

        let opts = parseOptions(arguments)
        guard let channelId = opts["--channel"], !channelId.isEmpty,
              let pidStr = opts["--parent-pid"], let pid = Int32(pidStr) else {
            // 인자 부족 → 안전하게 메인 모드로 폴백
            return .main
        }

        let channelName = opts["--channel-name"] ?? channelId
        let instanceId = opts["--instance-id"] ?? UUID().uuidString
        let frame = opts["--frame"].flatMap(parseFrame)
        let volume = opts["--volume"].flatMap(Float.init) ?? 1.0
        let muted = opts["--muted"] == "1" || arguments.contains("--muted")
        let borderless = opts["--borderless"] == "1"
        let hideFromDock = opts["--hide-from-dock"] == "1"

        let cfg = MultiLiveChildConfig(
            channelId: channelId,
            channelName: channelName,
            parentPID: pid,
            instanceId: instanceId,
            initialFrame: frame,
            initialVolume: max(0, min(1, volume)),
            startMuted: muted,
            borderless: borderless,
            hideFromDock: hideFromDock
        )
        return .multiLiveChild(cfg)
    }

    /// "--key value" 형식의 인자를 dictionary 로 변환
    private static func parseOptions(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let token = args[i]
            if token.hasPrefix("--"), i + 1 < args.count {
                let next = args[i + 1]
                if !next.hasPrefix("--") {
                    result[token] = next
                    i += 2
                    continue
                }
            }
            i += 1
        }
        return result
    }

    private static func parseFrame(_ raw: String) -> CGRect? {
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}

// MARK: - Distributed Notification Names (메인 ↔ 자식 IPC)

public enum MultiLiveIPC {
    /// 메인 → 자식: 자식 인스턴스 종료 요청
    /// userInfo: ["instanceId": String]
    public static let requestQuit = Notification.Name("dev.cview.multilive.child.quit")

    /// 자식 → 메인: 자식 인스턴스가 시작됨
    /// userInfo: ["instanceId": String, "channelId": String, "pid": Int32]
    public static let childDidLaunch = Notification.Name("dev.cview.multilive.child.didLaunch")

    /// 자식 → 메인: 자식 인스턴스가 종료됨
    /// userInfo: ["instanceId": String, "channelId": String, "reason": String]
    public static let childDidExit = Notification.Name("dev.cview.multilive.child.didExit")

    /// 메인 → 자식: 음량 변경
    /// userInfo: ["instanceId": String, "volume": Float]
    public static let setVolume = Notification.Name("dev.cview.multilive.child.setVolume")

    /// 메인 → 자식: 음소거 토글
    /// userInfo: ["instanceId": String, "muted": Bool]
    public static let setMuted = Notification.Name("dev.cview.multilive.child.setMuted")

    /// 메인 → 자식: 창 frame 변경 (자동 그리드/탭 배치)
    /// userInfo: ["instanceId": String, "x": Double, "y": Double, "w": Double, "h": Double]
    public static let setFrame = Notification.Name("dev.cview.multilive.child.setFrame")

    /// 메인 → 자식: 창 minimize/restore
    /// userInfo: ["instanceId": String, "minimized": Bool]
    public static let setMinimized = Notification.Name("dev.cview.multilive.child.setMinimized")

    /// 메인 → 자식: 창 chrome 변경 (보더리스 + Dock 아이콘 숨김)
    /// userInfo: ["instanceId": String, "borderless": Bool, "hideFromDock": Bool]
    public static let setChrome = Notification.Name("dev.cview.multilive.child.setChrome")
}
