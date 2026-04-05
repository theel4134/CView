// MARK: - MultiLiveEnginePool.swift
// CViewPlayer — VLC + AVPlayer 통합 엔진 풀
// 멀티라이브 세션 간 엔진 재사용으로 생성 비용 절감 및 리소스 관리

import Foundation
import CViewCore

/// 멀티라이브용 통합 엔진 풀 — VLC/AVPlayer 타입별 idle 큐 관리
public actor MultiLiveEnginePool {

    private let maxPoolSize: Int
    private var idleEngines: [PlayerEngineType: [any PlayerEngineProtocol]] = [
        .vlc: [],
        .avPlayer: [],
        .hlsjs: [],
    ]
    private var activeCount: [PlayerEngineType: Int] = [
        .vlc: 0,
        .avPlayer: 0,
        .hlsjs: 0,
    ]
    private let logger = AppLogger.player

    public init(maxPoolSize: Int) {
        self.maxPoolSize = maxPoolSize
    }

    /// 전체 활성 엔진 수 (타입 무관)
    public var totalActiveCount: Int {
        (activeCount[.vlc] ?? 0) + (activeCount[.avPlayer] ?? 0) + (activeCount[.hlsjs] ?? 0)
    }

    /// 타입별 미리 엔진 생성
    public func warmup(count: Int, type: PlayerEngineType) async {
        let idle = idleEngines[type]?.count ?? 0
        let active = activeCount[type] ?? 0
        let toCreate = min(count, maxPoolSize - idle - active)
        guard toCreate > 0 else { return }

        for _ in 0..<toCreate {
            let engine = await Self.makeEngine(type: type)
            idleEngines[type, default: []].append(engine)
        }
        logger.info("EnginePool: warmup \(type.rawValue) ×\(toCreate) (idle=\(idle + toCreate))")
    }

    /// 풀에서 유휴 엔진 획득 또는 새로 생성
    public func acquire(type: PlayerEngineType) async -> (any PlayerEngineProtocol)? {
        // idle 풀에서 꺼내기
        if var idle = idleEngines[type], !idle.isEmpty {
            let engine = idle.removeLast()
            idleEngines[type] = idle
            activeCount[type, default: 0] += 1
            logger.info("EnginePool: acquire \(type.rawValue) from idle (active=\(self.activeCount[type] ?? 0))")
            return engine
        }

        // 전체 풀 한도 체크
        let totalIdle = (idleEngines[.vlc]?.count ?? 0) + (idleEngines[.avPlayer]?.count ?? 0) + (idleEngines[.hlsjs]?.count ?? 0)
        guard totalActiveCount + totalIdle < maxPoolSize else {
            logger.warning("EnginePool: maxPoolSize(\(self.maxPoolSize)) 도달 — acquire 거부")
            return nil
        }

        // 새로 생성
        let engine = await Self.makeEngine(type: type)
        activeCount[type, default: 0] += 1
        logger.info("EnginePool: acquire \(type.rawValue) new (active=\(self.activeCount[type] ?? 0))")
        return engine
    }

    /// 엔진 풀 반납 — resetForReuse 후 idle 큐에 보관
    public func release(_ engine: any PlayerEngineProtocol) async {
        let type: PlayerEngineType
        if let vlc = engine as? VLCPlayerEngine {
            type = .vlc
            await MainActor.run { vlc.resetForReuse() }
        } else if let av = engine as? AVPlayerEngine {
            type = .avPlayer
            await MainActor.run { av.resetForReuse() }
        } else if let hlsjs = engine as? HLSJSPlayerEngine {
            type = .hlsjs
            await MainActor.run { hlsjs.resetForReuse() }
        } else {
            return
        }

        activeCount[type] = max(0, (activeCount[type] ?? 0) - 1)

        let idle = idleEngines[type]?.count ?? 0
        if idle < maxPoolSize {
            idleEngines[type, default: []].append(engine)
            logger.info("EnginePool: release \(type.rawValue) → idle (idle=\(idle + 1), active=\(self.activeCount[type] ?? 0))")
        } else {
            logger.info("EnginePool: release \(type.rawValue) — idle 풀 초과, 폐기")
        }
    }

    /// 모든 유휴 엔진 정리
    public func drain() async {
        for (type, engines) in idleEngines {
            for engine in engines {
                if let vlc = engine as? VLCPlayerEngine {
                    await MainActor.run { vlc.resetForReuse() }
                } else if let av = engine as? AVPlayerEngine {
                    await MainActor.run { av.resetForReuse() }
                } else if let hlsjs = engine as? HLSJSPlayerEngine {
                    await MainActor.run { hlsjs.resetForReuse() }
                }
            }
            logger.info("EnginePool: drain \(type.rawValue) ×\(engines.count)")
        }
        idleEngines[.vlc]?.removeAll()
        idleEngines[.avPlayer]?.removeAll()
        idleEngines[.hlsjs]?.removeAll()
    }

    /// 엔진 팩토리 — VLC/HLS.js는 MainActor에서 생성 필요 (NSView 포함)
    private static func makeEngine(type: PlayerEngineType) async -> any PlayerEngineProtocol {
        switch type {
        case .vlc:
            let engine = await MainActor.run { VLCPlayerEngine() }
            await MainActor.run { engine.streamingProfile = .multiLive }
            return engine
        case .avPlayer:
            let engine = await MainActor.run { AVPlayerEngine() }
            return engine
        case .hlsjs:
            let engine = await MainActor.run { HLSJSPlayerEngine() }
            await MainActor.run { engine.streamingProfile = .multiLive }
            return engine
        }
    }
}
