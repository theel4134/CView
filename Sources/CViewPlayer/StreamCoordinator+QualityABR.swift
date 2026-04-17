// MARK: - StreamCoordinator+QualityABR.swift
// CViewPlayer — 1080p+ABR 하이브리드 + ABR 대역폭 + 진단

import Foundation
import CViewCore

extension StreamCoordinator {

    // MARK: - 1080p + ABR Hybrid

    /// VLC 엔진의 적응형 화질 전환 요청을 처리합니다.
    /// - downgrade: 대역폭 부족 → 한 단계 낮은 화질로 전환
    /// - upgrade: 버퍼 안정 → 원래 화질로 복귀
    public func handleQualityAdaptation(_ action: QualityAdaptationAction) async {
        guard let master = _masterPlaylist, master.variants.count > 1 else { return }

        // [Fix 27] 사용자 수동 선택 잠금: ABR의 downgrade/upgrade 모두 무시
        if _userSelectedVariant != nil {
            if case .downgrade(let reason) = action {
                logger.debug("User quality lock: downgrade 무시 (\(reason))")
            } else if case .upgrade(let reason) = action {
                logger.debug("User quality lock: upgrade 무시 (\(reason))")
            }
            return
        }

        // [Quality Lock] 최고 화질 모드 — 하향 요청 무시, 상향은 허용 (복귀만 유효)
        if config.forceHighestQuality {
            if case .downgrade(let reason) = action {
                logger.debug("Quality lock: downgrade 무시 (\(reason))")
                return
            }
        }

        let sortedVariants = master.variants.sorted { $0.bandwidth > $1.bandwidth }

        switch action {
        case .downgrade(let reason):
            guard !_isQualityDegraded else { return }

            if _preferredQualityVariant == nil, let current = sortedVariants.first(where: {
                $0.resolution.contains("1080")
            }) ?? sortedVariants.first {
                _preferredQualityVariant = current
            }

            let fallbackVariant = sortedVariants.first(where: { $0.resolution.contains("720") })
                ?? sortedVariants.dropFirst().first

            guard let targetVariant = fallbackVariant else { return }

            _isQualityDegraded = true
            _qualityRecoveryTask?.cancel()

            logger.warning("ABR 하이브리드: 화질 하향 → \(targetVariant.qualityLabel) (\(reason))")

            do {
                try await switchQuality(to: targetVariant)
                emitEvent(.qualityChanged(qualityFromVariant(targetVariant)))

                // [Fix 22B] 버퍼 기반 화질 복귀: bufferHealth + VLC 실제 버퍼 길이 이중 확인
                // 기존: bufferHealth >= 0.7만 확인 → 버퍼 짧아도 복귀 → 즉시 재강등 진동
                _qualityRecoveryTask = Task { [weak self] in
                    // 최소 8초 대기 (화질 전환 직후 안정화 + ABR minSwitchInterval 경과)
                    try? await Task.sleep(for: .seconds(8))
                    guard let self, !Task.isCancelled else { return }

                    // bufferHealth ≥ 0.7 + VLC 버퍼 ≥ 4초로 3회 연속 확인되면 복귀
                    var stableCount = 0
                    for _ in 0..<12 {  // 최대 ~36초 대기
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        
                        let healthOk = self._lastBufferHealth >= 0.7
                        // [Fix 22B] VLC 실제 버퍼 길이 확인 (recordBandwidthSample에서 갱신)
                        let bufferOk = self._lastVLCBufferLength >= 4.0
                        
                        if healthOk && bufferOk {
                            stableCount += 1
                            if stableCount >= 3 {
                                await self.handleQualityAdaptation(.upgrade(reason: "버퍼 안정 확인 후 복귀"))
                                return
                            }
                        } else {
                            stableCount = 0  // 불안정하면 카운터 리셋
                        }
                    }
                    // [Fix 22B] 36초 내 안정화 안 되면 bufferHealth만 확인 후 복귀
                    // (무한 대기 방지, 단 최소 안전성 확인)
                    if self._lastBufferHealth >= 0.5 {
                        await self.handleQualityAdaptation(.upgrade(reason: "최대 대기시간 초과 복귀"))
                    }
                }
            } catch {
                _isQualityDegraded = false
                logger.warning("ABR 하이브리드: 화질 하향 실패: \(error.localizedDescription)")
            }

        case .upgrade(let reason):
            guard _isQualityDegraded else { return }

            guard let preferredVariant = _preferredQualityVariant else {
                _isQualityDegraded = false
                return
            }

            _qualityRecoveryTask?.cancel()

            logger.info("ABR 하이브리드: 화질 복귀 → \(preferredVariant.qualityLabel) (\(reason))")

            do {
                try await switchQuality(to: preferredVariant)
                _isQualityDegraded = false
                // [Fix 22D] 화질 복귀 후 10초 쿨다운 — ABR 긴급 강등 차단
                _qualityRecoveryCooldownUntil = Date().addingTimeInterval(10.0)
                emitEvent(.qualityChanged(qualityFromVariant(preferredVariant)))
            } catch {
                logger.warning("ABR 하이브리드: 화질 복귀 실패, 10초 후 재시도")
                _qualityRecoveryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard let self, !Task.isCancelled else { return }
                    await self.handleQualityAdaptation(.upgrade(reason: "복귀 재시도"))
                }
            }
        }
    }

    /// 현재 화질 하향 상태 여부
    public var isQualityDegraded: Bool { _isQualityDegraded }

    // MARK: - ABR

    /// Record bandwidth sample for ABR
    /// - Parameters:
    ///   - bytesLoaded: 수신 바이트 수
    ///   - duration: 측정 구간 (초)
    ///   - bufferHealth: VLC 버퍼 건강도 0.0~1.0 (nil이면 bandwidth-only)
    public func recordBandwidthSample(bytesLoaded: Int, duration: TimeInterval, bufferHealth: Double? = nil) async {
        // 버퍼 건강도 갱신 (화질 복귀 판단에 사용)
        if let bh = bufferHealth { _lastBufferHealth = bh }

        let sample = ABRController.BandwidthSample(
            bytesLoaded: bytesLoaded,
            duration: duration
        )
        await abrController?.recordSample(sample)

        // [Fix 22A] 버퍼 인지형 ABR: 실제 VLC 버퍼 길이(duration - currentTime) 사용
        // 기존 bufferHealth × liveCaching 추정은 0.25~0.5s로 과소평가 → ABR 긴급 강등 오발
        // 실제 VLC 파이프라인 버퍼(수 초)를 직접 측정하여 정확한 sftm 계산
        let context: ABRController.PlaybackContext?
        if let bh = bufferHealth, bh >= 0 {
            let currentRate = await lowLatencyController?.currentRate ?? 1.0
            // 실제 VLC 버퍼 길이 측정 (duration - currentTime)
            let actualBuffer: TimeInterval
            if let engine = playerEngine, engine.isPlaying {
                let d = engine.duration
                let c = engine.currentTime
                if d > 0, c > 0, (d - c) > 0, (d - c) < 60 {
                    // 재생 속도 반영: 가속 중에는 버퍼 소비가 빨라지므로 실효 버퍼 축소
                    actualBuffer = (d - c) / max(currentRate, 0.5)
                } else {
                    // VLC 메트릭 불가 시 bufferHealth 기반 폴백 (최소 2초 보장)
                    actualBuffer = max(bh * 4.0, 2.0) / max(currentRate, 0.5)
                }
            } else {
                actualBuffer = max(bh * 4.0, 2.0) / max(currentRate, 0.5)
            }
            // [Fix 22B] VLC 버퍼 길이 저장 (화질 복귀 판단용)
            _lastVLCBufferLength = actualBuffer * max(currentRate, 0.5)  // rate 보정 전 원래 길이
            context = ABRController.PlaybackContext(
                bufferLength: actualBuffer,
                lastFetchDuration: duration,
                lastSegmentDuration: 2.0  // 치지직 기본 세그먼트 길이
            )
        } else {
            context = nil
        }

        if let decision = await abrController?.recommendLevel(context: context) {
            // [Fix 27] 사용자 수동 선택 잠금: ABR switchUp/switchDown 모두 무시
            if _userSelectedVariant != nil {
                return
            }
            switch decision {
            case .switchUp(let bandwidth, let reason):
                emitEvent(.abrDecision(.switchUp(toBandwidth: bandwidth, reason: reason)))
                if let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) {
                    do {
                        try await switchQuality(to: variant)
                    } catch {
                        logger.warning("ABR switchUp failed (\(reason)) \(bandwidth)bps: \(error.localizedDescription)")
                    }
                }
            case .switchDown(let bandwidth, let reason):
                // [Quality Lock] 최고 화질 모드: ABR switchDown 전면 무시
                if config.forceHighestQuality {
                    logger.debug("Quality lock: ABR switchDown 무시 (\(reason))")
                    break
                }
                // [Fix 22D] 화질 복귀 직후 쿨다운 기간에는 ABR 강등 무시 (진동 방지)
                if Date() < _qualityRecoveryCooldownUntil {
                    logger.debug("ABR switchDown 무시: 화질 복귀 쿨다운 중 (\(reason))")
                    break
                }
                emitEvent(.abrDecision(.switchDown(toBandwidth: bandwidth, reason: reason)))
                if let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) {
                    do {
                        // [Fix 26] ABR switchDown에도 복구 메커니즘 연결
                        // 기존: switchQuality만 호출 → _isQualityDegraded 미설정 → 자동 복구 불가
                        // 개선: preferred 저장 + degraded 플래그 + 복구 타이머 + 화질 프로빙 시작
                        if !_isQualityDegraded {
                            if _preferredQualityVariant == nil {
                                let sorted = _masterPlaylist?.variants.sorted(by: { $0.bandwidth > $1.bandwidth })
                                _preferredQualityVariant = sorted?.first(where: { $0.resolution.contains("1080") }) ?? sorted?.first
                            }
                            _isQualityDegraded = true
                            logger.info("ABR switchDown: 화질 하향 감지 → \(variant.qualityLabel) (\(reason)), 복구 타이머 시작")
                        }
                        try await switchQuality(to: variant)
                        // 복구 타이머 갱신 (더 낮은 화질로 내려갈 때마다 리셋)
                        _qualityRecoveryTask?.cancel()
                        _qualityRecoveryTask = Task {
                            try? await Task.sleep(for: .seconds(10))
                            guard !Task.isCancelled else { return }
                            var stableCount = 0
                            for _ in 0..<20 {  // 최대 ~60초 대기 (ABR은 장기 모니터링 필요)
                                try? await Task.sleep(for: .seconds(3))
                                guard !Task.isCancelled else { return }
                                let healthOk = _lastBufferHealth >= 0.7
                                let bufferOk = _lastVLCBufferLength >= 4.0
                                if healthOk && bufferOk {
                                    stableCount += 1
                                    if stableCount >= 3 {
                                        await handleQualityAdaptation(.upgrade(reason: "ABR switchDown 후 버퍼 안정 → 복귀"))
                                        return
                                    }
                                } else {
                                    stableCount = 0
                                }
                            }
                            // 60초 내 안정화 안 되면 프로빙으로 전환
                            startQualityProbeTimer()
                        }
                    } catch {
                        logger.warning("ABR switchDown failed (\(reason)) \(bandwidth)bps: \(error.localizedDescription)")
                    }
                }
            case .maintain:
                break
            }
        }
    }

    // MARK: - Quality Probe Timer (Death Spiral 해소)

    /// [Fix 26] 화질 프로빙 타이머: 장시간 저화질 고정 시 주기적으로 상위 화질 시도
    /// EWMA가 현재 (저)화질 throughput에 수렴하여 switchUp이 불가능해지는
    /// "death spiral" 현상을 해소합니다.
    func startQualityProbeTimer() {
        _qualityProbeTask?.cancel()
        // [Fix 27] 사용자 수동 선택 잠금: 프로빙 시작하지 않음
        guard _userSelectedVariant == nil else { return }
        guard _isQualityDegraded, let preferred = _preferredQualityVariant else { return }
        guard let master = _masterPlaylist, master.variants.count > 1 else { return }

        _qualityProbeTask = Task {
            // 최초 3분 대기
            try? await Task.sleep(for: .seconds(180))

            while !Task.isCancelled {
                guard _isQualityDegraded else { break }

                // 버퍼 안정 확인 (최근 bufferHealth >= 0.6)
                guard _lastBufferHealth >= 0.6 else {
                    try? await Task.sleep(for: .seconds(60))
                    continue
                }

                // 현재 화질보다 한 단계 상위 variant 선택
                let sortedVariants = _masterPlaylist?.variants.sorted(by: { $0.bandwidth < $1.bandwidth }) ?? []
                guard let currentLevel = await abrController?.selectedLevel else {
                    try? await Task.sleep(for: .seconds(180))
                    continue
                }
                let currentBW = currentLevel.bandwidth
                guard let nextVariant = sortedVariants.first(where: { $0.bandwidth > currentBW }) else {
                    // 이미 최고 화질 — 프로빙 불필요
                    break
                }

                logger.info("Quality probe: \(currentLevel.qualityLabel) → \(nextVariant.qualityLabel) 프로빙 시작")

                // ABR EWMA에 목표 비트레이트 주입 (switchUp 조건 통과용)
                await abrController?.injectSyntheticSample(
                    targetBitrate: Double(nextVariant.bandwidth)
                )

                // 상위 화질로 전환 시도
                do {
                    try await switchQuality(to: nextVariant)
                    emitEvent(.qualityChanged(qualityFromVariant(nextVariant)))
                } catch {
                    logger.warning("Quality probe: 전환 실패 — \(error.localizedDescription)")
                    try? await Task.sleep(for: .seconds(180))
                    continue
                }

                // 15초 안정성 확인
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }

                let probeHealthOk = _lastBufferHealth >= 0.5
                let probeBufferOk = _lastVLCBufferLength >= 2.0

                if probeHealthOk && probeBufferOk {
                    logger.info("Quality probe: \(nextVariant.qualityLabel) 안정 확인 ✓")
                    // preferred에 도달했으면 프로빙 종료 + degraded 해제
                    if nextVariant.bandwidth >= preferred.bandwidth {
                        _isQualityDegraded = false
                        _qualityRecoveryCooldownUntil = Date().addingTimeInterval(10.0)
                        logger.info("Quality probe: 선호 화질 복귀 완료 → 프로빙 종료")
                        break
                    }
                    // 아직 preferred 미도달 — 다음 프로빙까지 2분 대기
                    try? await Task.sleep(for: .seconds(120))
                } else {
                    // 불안정 — 원래 화질로 복귀
                    logger.warning("Quality probe: \(nextVariant.qualityLabel) 불안정 (bh=\(String(format: "%.2f", self._lastBufferHealth)) buf=\(String(format: "%.1f", self._lastVLCBufferLength))s) → 원복")
                    if let fallback = sortedVariants.last(where: { $0.bandwidth <= currentBW }) ?? sortedVariants.first {
                        try? await switchQuality(to: fallback)
                    }
                    // 3분 후 재시도
                    try? await Task.sleep(for: .seconds(180))
                }
            }
        }
    }

    // MARK: - Private

    func selectInitialQuality(from master: MasterPlaylist) -> MasterPlaylist.Variant {
        // [Quality Lock] 최고 화질 모드: 1080p60 우선, 없으면 최고 bandwidth
        if config.forceHighestQuality {
            if let target = select1080p60Variant(from: master.variants) {
                return target
            }
        }

        if let preferred = config.preferredQuality {
            if let match = master.variants.first(where: { $0.qualityLabel == preferred.displayName }) {
                return match
            }
        }

        let midIndex = master.variants.count / 2
        return master.variants[midIndex]
    }

    // MARK: - Stream Diagnostic (DEBUG)

    #if DEBUG
    /// CDN 스트림 진단 실행.
    /// M3U8 구조(EXT-X-MAP), 세그먼트 Content-Type, magic bytes를 분석하여
    /// 프록시 바이패스 가능 여부를 판정합니다.
    public func runStreamDiagnostic(url: URL? = nil) async {
        guard let targetURL = url ?? _streamURL else {
            logger.warning("[Diagnostic] No stream URL available")
            return
        }

        logger.info("[Diagnostic] Starting CDN stream diagnostic...")
        let diagnostic = ChzzkStreamDiagnostic()

        do {
            let result = try await diagnostic.runFullDiagnostic(masterURL: targetURL)

            let report = result.summary
            logger.info("[Diagnostic] Result:\n\(report, privacy: .public)")

            let reportPath = "/tmp/chzzk_diagnostic.txt"
            try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            logger.info("[Diagnostic] Report saved to \(reportPath, privacy: .public)")

            let feasibility = result.proxyBypassFeasibility
            if feasibility.feasible {
                logger.info("[Diagnostic] ✅ Proxy bypass appears FEASIBLE (confidence: \(feasibility.confidence.rawValue, privacy: .public))")
            } else {
                logger.warning("[Diagnostic] ❌ Proxy bypass NOT recommended (confidence: \(feasibility.confidence.rawValue, privacy: .public))")
            }
        } catch {
            logger.error("[Diagnostic] Failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}
