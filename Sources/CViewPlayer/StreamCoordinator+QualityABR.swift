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

                _qualityRecoveryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard let self, !Task.isCancelled else { return }
                    await self.handleQualityAdaptation(.upgrade(reason: "10초 타이머 자동 복귀"))
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
    public func recordBandwidthSample(bytesLoaded: Int, duration: TimeInterval) async {
        let sample = ABRController.BandwidthSample(
            bytesLoaded: bytesLoaded,
            duration: duration
        )
        await abrController?.recordSample(sample)

        if let decision = await abrController?.recommendLevel() {
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
                emitEvent(.abrDecision(.switchDown(toBandwidth: bandwidth, reason: reason)))
                if let variant = _masterPlaylist?.variants.first(where: { $0.bandwidth == bandwidth }) {
                    do {
                        try await switchQuality(to: variant)
                    } catch {
                        logger.warning("ABR switchDown failed (\(reason)) \(bandwidth)bps: \(error.localizedDescription)")
                    }
                }
            case .maintain:
                break
            }
        }
    }

    // MARK: - Private

    func selectInitialQuality(from master: MasterPlaylist) -> MasterPlaylist.Variant {
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
