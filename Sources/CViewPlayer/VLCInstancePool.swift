// MARK: - VLCInstancePool.swift
// CViewPlayer — 멀티라이브용 VLC 인스턴스 풀링
//
// [설계 원칙]
// • VLCPlayerEngine 초기화 비용을 절감하기 위해 미리 생성된 인스턴스를 풀에서 대여/반납
// • actor로 구현하여 Swift 6 strict concurrency 안전성 보장
// • release 시 resetForReuse() 호출 후 유휴 상태로 전환
// • drain()으로 전체 풀 해제 (멀티라이브 종료, 메모리 경고 시)

import Foundation
import CViewCore

// MARK: - VLC Instance Pool

/// 멀티라이브용 VLCPlayerEngine 인스턴스 풀.
/// 최대 `maxPoolSize`개의 엔진을 관리하며, acquire/release 패턴으로 재사용한다.
public actor VLCInstancePool {

    // MARK: - Configuration

    public let maxPoolSize: Int

    // MARK: - State

    private var idleEngines: [VLCPlayerEngine] = []
    private var activeEngines: Set<ObjectIdentifier> = []
    private var allEngines: [ObjectIdentifier: VLCPlayerEngine] = [:]

    private let logger = AppLogger.player

    // MARK: - Init

    public init(maxPoolSize: Int = 4) {
        self.maxPoolSize = maxPoolSize
    }

    // MARK: - Stats

    public var idleCount: Int { idleEngines.count }
    public var activeCount: Int { activeEngines.count }
    public var totalCount: Int { allEngines.count }

    // MARK: - Acquire

    /// 유휴 엔진을 반환하거나, 풀에 여유가 있으면 새로 생성하여 반환.
    /// - Returns: 사용 가능한 VLCPlayerEngine, 풀이 가득 차면 nil
    public func acquire() async -> VLCPlayerEngine? {
        // 유휴 엔진 재사용
        if let engine = idleEngines.popLast() {
            let id = ObjectIdentifier(engine)
            activeEngines.insert(id)
            logger.info("VLCInstancePool: acquire (재사용) — active=\(self.activeEngines.count) idle=\(self.idleEngines.count)")
            return engine
        }

        // 풀 여유 공간 확인 후 신규 생성 (NSView 생성은 메인 스레드 필수)
        guard allEngines.count < maxPoolSize else {
            logger.warning("VLCInstancePool: acquire 실패 — 풀 최대 용량 도달 (\(self.maxPoolSize))")
            return nil
        }

        let engine = await MainActor.run { VLCPlayerEngine() }
        let id = ObjectIdentifier(engine)
        allEngines[id] = engine
        activeEngines.insert(id)
        logger.info("VLCInstancePool: acquire (신규 생성) — total=\(self.allEngines.count) active=\(self.activeEngines.count)")
        return engine
    }

    // MARK: - Release

    /// 엔진을 풀로 반납. 재생 중지 후 유휴 상태로 전환.
    public func release(_ engine: VLCPlayerEngine) async {
        let id = ObjectIdentifier(engine)
        guard activeEngines.remove(id) != nil else {
            logger.warning("VLCInstancePool: release — 활성 목록에 없는 엔진 반납 (무시)")
            return
        }
        // ⚠️ MainActor에서 동기적으로 resetForReuse 실행해야
        // async 디스패치 시 엔진이 idle 풀에 돌아간 후 acquire() 되면
        // 늦은 cleanup이 새 재생을 죽이는 레이스 컨디션 발생
        await MainActor.run { engine.resetForReuse() }
        // [VLC 안정 컨테이너 패턴] resetForReuse() 내부의 deferred 작업 완료 대기.
        // resetForReuse()는 VLC 크래시 방지를 위해 media=nil을
        // DispatchQueue.main.async로 defer한다. 이 비동기 블록이 완료되기 전에
        // 엔진을 idle 풀에 넣으면, acquire() 후 새 재생이 시작된 뒤 늦은
        // media=nil이 실행되어 재생을 죽이는 레이스 컨디션이 발생한다.
        // MainActor.run 2회 호출로 deferred 블록 실행을 보장한다.
        // (1차 await: deferred 블록 enqueue 완료, 2차 await: deferred 블록 실행 완료)
        await MainActor.run {}  // DispatchQueue.main.async 블록 소진 대기
        await MainActor.run {}  // 추가 안전 마진
        idleEngines.append(engine)
        logger.info("VLCInstancePool: release — active=\(self.activeEngines.count) idle=\(self.idleEngines.count)")
    }

    // MARK: - Warmup

    /// 지정 수만큼 유휴 인스턴스를 백그라운드에서 미리 생성.
    /// 1개씩 순차 생성하여 메인 스레드 과부하 방지.
    public func warmup(count: Int = 2) async {
        let needed = min(count, maxPoolSize - allEngines.count)
        guard needed > 0 else {
            logger.info("VLCInstancePool: warmup 스킵 — 충분한 인스턴스 보유 (total=\(self.allEngines.count))")
            return
        }

        for i in 0..<needed {
            let engine = await MainActor.run { VLCPlayerEngine() }
            let id = ObjectIdentifier(engine)
            allEngines[id] = engine
            idleEngines.append(engine)
            if i < needed - 1 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms — 메인 스레드 여유 확보
            }
        }
        logger.info("VLCInstancePool: warmup \(needed)개 생성 완료 — total=\(self.allEngines.count) idle=\(self.idleEngines.count)")
    }

    // MARK: - Drain

    /// 모든 풀 인스턴스 정리 (멀티라이브 종료, 메모리 경고 시).
    public func drain() async {
        let count = allEngines.count
        // MainActor에서 동기적으로 정리하여 VLC 내부 스레드 레이스 방지
        let allIdle = idleEngines
        let allActive = activeEngines.compactMap { allEngines[$0] }
        await MainActor.run {
            for engine in allIdle { engine.resetForReuse() }
            for engine in allActive { engine.resetForReuse() }
        }
        idleEngines.removeAll()
        activeEngines.removeAll()
        allEngines.removeAll()
        logger.info("VLCInstancePool: drain — \(count)개 해제 완료")
    }

    // MARK: - Memory Pressure

    /// 메모리 압박 시 유휴 인스턴스 축소.
    public func reducePool(keepCount: Int = 0) async {
        let remove = max(0, idleEngines.count - keepCount)
        guard remove > 0 else { return }
        let toRemove = Array(idleEngines.suffix(remove))
        await MainActor.run {
            for engine in toRemove { engine.stop() }
        }
        for engine in toRemove {
            let id = ObjectIdentifier(engine)
            allEngines.removeValue(forKey: id)
        }
        idleEngines.removeLast(remove)
        logger.info("VLCInstancePool: reducePool — \(remove)개 제거, 남은 idle=\(self.idleEngines.count)")
    }
}
