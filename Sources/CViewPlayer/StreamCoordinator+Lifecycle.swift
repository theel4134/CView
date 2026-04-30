// MARK: - StreamCoordinator+Lifecycle.swift
// CViewPlayer — 스트림 시작/종료/품질 전환 + AVPlayer 매니페스트 해석

import Foundation
import CViewCore

extension StreamCoordinator {

    // MARK: - Stream Lifecycle

    /// Start playing a stream from URL
    public func startStream(url: URL) async throws {
        _streamURL = url
        _startTime = Date()

        updatePhase(.connecting)

        do {
            var playbackURL = url
            let isVLCEngine = playerEngine is VLCPlayerEngine
            let isAVEngine = playerEngine is AVPlayerEngine

            // [Stream Proxy Mode] 사용자 선택에 따라 Content-Type 교정 전략 결정.
            // 호환되지 않는 (엔진 × 모드) 조합은 자동으로 .localProxy 로 폴백.
            let resolvedMode = Self.resolveProxyMode(
                requested: config.streamProxyMode,
                isVLC: isVLCEngine,
                isAV: isAVEngine,
                url: url
            )

            // 엔진에 모드 전파 (avInterceptor / avAssetDownload / urlProtocolHook 처리에 사용)
            if let av = playerEngine as? AVPlayerEngine {
                av.streamProxyMode = resolvedMode
            }
            if let vlc = playerEngine as? VLCPlayerEngine {
                vlc.streamProxyMode = resolvedMode
            }

            // .urlProtocolHook 모드는 글로벌 등록만 보장 (이미 등록되어 있으면 no-op)
            if resolvedMode == .urlProtocolHook {
                CViewHTTPURLProtocol.registerIfNeeded()
            }

            // 로컬 프록시는 .localProxy 모드일 때만 시작
            if resolvedMode == .localProxy, LocalStreamProxy.needsProxy(for: url), let host = url.host {
                do {
                    try await streamProxy.start(for: host)
                    _isProxyActive = true
                    streamProxy.onUpstreamAuthFailure = { [weak self] in
                        Task { [weak self] in
                            await self?.triggerReconnect(reason: "CDN 403 토큰 만료 감지")
                        }
                    }
                    logger.info("Proxy[\(resolvedMode.rawValue, privacy: .public)]: 시작 (host=\(host, privacy: .public) → localhost:\(self.streamProxy.port, privacy: .public))")
                } catch {
                    _isProxyActive = false
                    logger.warning("Proxy: 시작 실패 — 직접 재생 시도 (\(error.localizedDescription, privacy: .public))")
                }
            } else {
                _isProxyActive = false
                logger.info("Proxy mode = \(resolvedMode.rawValue, privacy: .public) (로컬 프록시 미사용)")
            }

            if isVLCEngine {
                // [Fix 16g] VLC에 chunklist(미디어 플레이리스트) URL 직접 전달
                _currentVariantURL = url  // 원본 CDN URL 보존 (재연결용)

                // [Opt: Single VLC] 프리페치 매니페스트가 있으면 네트워크 재요청 생략
                if let prefetchedMaster = _masterPlaylist, !prefetchedMaster.variants.isEmpty {
                    let sortedVariants = prefetchedMaster.variants.sorted { $0.bandwidth > $1.bandwidth }
                    let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                        ?? sortedVariants.first

                    // ABR 레벨 설정 + CDN 워밍 병렬 실행 (독립 작업)
                    async let levelsTask: Void = {
                        await abrController?.setLevels(prefetchedMaster.variants)
                    }()
                    async let warmUpTask: Void = warmUpCDNConnection(url: url)
                    _ = await (levelsTask, warmUpTask)

                    if let variant = target {
                        _currentVariantURL = variant.uri
                        _currentQuality = qualityFromVariant(variant)
                        _preferredQualityVariant = variant
                        emitEvent(.qualitySelected(_currentQuality!))
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: variant.uri)
                        } else {
                            playbackURL = variant.uri
                        }
                        logger.info("VLC: [Opt] 프리페치 매니페스트에서 variant 해석 → \(variant.qualityLabel) (네트워크 절약)")
                    } else {
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: url)
                        }
                    }
                } else {
                    // 프리페치 캐시 없음 — 기존 경로: CDN 워밍 + variant 해석 병렬 실행
                    async let warmUpTask: Void = warmUpCDNConnection(url: url)
                    async let variantTask = resolveHighestQualityVariant(from: url)

                    let (_, resolvedVariant) = await (warmUpTask, variantTask)

                    if let variantURL = resolvedVariant {
                        _currentVariantURL = variantURL
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: variantURL)
                        } else {
                            playbackURL = variantURL
                        }
                        logger.info("VLC: [Fix 16g] chunklist URL 직접 전달 → \(variantURL.lastPathComponent, privacy: .public)")
                    } else {
                        if _isProxyActive {
                            playbackURL = streamProxy.proxyURL(from: url)
                        }
                        logger.warning("VLC: [Fix 16g] variant 해석 실패, 마스터 URL 폴백")
                    }
                }
            } else {
                // AVPlayer / HLS.js: 마스터 URL을 프록시 경유로 전달 (내장 ABR 활용)
                if let prefetchedMaster = _masterPlaylist, !prefetchedMaster.variants.isEmpty {
                    await resolveAVPlayerInitialQuality(from: prefetchedMaster)
                } else if !(playerEngine is HLSJSPlayerEngine) {
                    // HLS.js는 자체적으로 매니페스트를 파싱하므로 별도 해석 불필요
                    await resolveAVPlayerManifest(from: url)
                }

                // [Quality Lock] AVPlayer 의 내장 ABR 은 preferredPeakBitRate/Resolution 을
                // **상한** 으로만 취급하므로, 초기 대역폭 추정이 보수적이면 480p 변종으로 고정된다.
                // 화질 잠금(forceHighestQuality=true) 모드에서는 1080p60 variant URL 을 직접 전달하여
                // AVPlayer ABR 을 우회하고 1080p 를 항상 유지한다.
                let isAVPlayer = playerEngine is AVPlayerEngine
                if isAVPlayer,
                   config.forceHighestQuality,
                   let variant = _preferredQualityVariant {
                    _currentVariantURL = variant.uri
                    playbackURL = _isProxyActive
                        ? streamProxy.proxyURL(from: variant.uri)
                        : variant.uri
                    let fpsStr = variant.frameRate.map { "\(Int($0))fps" } ?? ""
                    logger.info("AVPlayer: [Quality Lock] variant URL 직접 전달 → \(variant.qualityLabel) \(fpsStr) (\(variant.bandwidth / 1000)kbps)")
                } else if _isProxyActive {
                    playbackURL = streamProxy.proxyURL(from: url)
                }
            }

            if let engine = playerEngine {
                try await engine.play(url: playbackURL)
                updatePhase(.playing)
            } else {
                updatePhase(.error("Player engine unavailable"))
                return
            }

            // 백그라운드에서 매니페스트 파싱 (품질 정보 UI용)
            if _masterPlaylist == nil {
                loadManifestInfo(from: url)
            }

            // 매니페스트 주기적 갱신 타이머 시작
            // VLC는 기존과 동일하게 토큰/variant URL을 주기적으로 갱신하고,
            // AVPlayer는 최고 화질 고정 모드에서 variant URL을 직접 사용하므로
            // 장시간 재생 시 URL 만료로 멈춤화면이 생기지 않도록 동일하게 갱신한다.
            let needsPinnedManifestRefresh = isVLCEngine || ((playerEngine is AVPlayerEngine) && config.forceHighestQuality)
            if needsPinnedManifestRefresh {
                startManifestRefreshTimer()
            }

            // 저지연 싱크: 백그라운드에서 비동기 실행
            if config.enableLowLatency {
                Task { [weak self] in await self?.startLowLatencySync() }
            } else if isVLCEngine {
                // 멀티라이브 등 PID 제어 없이 PDT 모니터링만 (레이턴시 측정용)
                Task { [weak self] in await self?.startPDTMonitoring() }
            }

            logger.info("Stream started: \(LogMask.url(url), privacy: .private)")

        } catch {
            updatePhase(.error(error.localizedDescription))
            throw error
        }
    }

    /// 마스터 매니페스트를 파싱하여 1080p (또는 최고 해상도) variant URL을 반환합니다.
    private func resolveHighestQualityVariant(from masterURL: URL) async -> URL? {
        do {
            var request = URLRequest(url: masterURL)
            request.timeoutInterval = 5
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")

            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""

            guard content.contains("#EXT-X-STREAM-INF") else {
                logger.info("VLC: Single media playlist (no variants) — using directly")
                return nil
            }

            let master = try await hlsParser.parseMasterPlaylist(content: content, baseURL: masterURL)
            _masterPlaylist = master
            await abrController?.setLevels(master.variants)

            let sortedVariants = master.variants.sorted { $0.bandwidth > $1.bandwidth }
            let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                ?? sortedVariants.first

            if let variant = target {
                _currentQuality = qualityFromVariant(variant)
                _preferredQualityVariant = variant
                emitEvent(.qualitySelected(_currentQuality!))
                logger.info("VLC: Resolved variant → \(variant.qualityLabel) (\(variant.bandwidth / 1000)kbps) \(variant.resolution)")
                return variant.uri
            }

            return nil
        } catch {
            logger.warning("VLC 1080p variant resolution failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - AVPlayer 1080p 60fps 초기 품질 해석 [Phase 4]

    private func resolveAVPlayerInitialQuality(from master: MasterPlaylist) async {
        await abrController?.setLevels(master.variants)

        guard let variant = select1080p60Variant(from: master.variants) else { return }

        _currentQuality = qualityFromVariant(variant)
        _preferredQualityVariant = variant
        emitEvent(.qualitySelected(_currentQuality!))
        logger.info("AVPlayer: [Phase 4] 프리페치 매니페스트 → \(variant.qualityLabel) \(variant.frameRate.map { "\(Int($0))fps" } ?? "") (\(variant.bandwidth / 1000)kbps)")
    }

    private func resolveAVPlayerManifest(from masterURL: URL) async {
        do {
            var request = URLRequest(url: masterURL)
            request.timeoutInterval = 3
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")

            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""

            guard content.contains("#EXT-X-STREAM-INF") else { return }

            let master = try await hlsParser.parseMasterPlaylist(content: content, baseURL: masterURL)
            _masterPlaylist = master

            await resolveAVPlayerInitialQuality(from: master)
            logger.info("AVPlayer: [Phase 4] 매니페스트 파싱 완료 → variants: \(master.variants.count)개")
        } catch {
            logger.debug("AVPlayer: 매니페스트 사전 파싱 실패 (무시): \(error.localizedDescription)")
        }
    }

    /// 1080p 60fps variant를 우선 선택하는 공통 선택 로직.
    func select1080p60Variant(from variants: [MasterPlaylist.Variant]) -> MasterPlaylist.Variant? {
        let sorted = variants.sorted { $0.bandwidth > $1.bandwidth }

        // 1순위: 1080p && 60fps
        if let target = sorted.first(where: {
            $0.resolution.contains("1080") && ($0.frameRate ?? 0) >= 59.0
        }) {
            return target
        }

        // 2순위: 1080p (아무 프레임레이트)
        if let target = sorted.first(where: { $0.resolution.contains("1080") }) {
            return target
        }

        // 3순위: 최고 bandwidth
        return sorted.first
    }

    /// CDN 엣지 서버에 HEAD 요청을 보내 TCP/TLS 연결을 사전 수립합니다.
    private func warmUpCDNConnection(url: URL) async {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 3
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            let (_, response) = try await hlsSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                logger.info("CDN 워밍 완료: \(url.host ?? "unknown") → HTTP \(httpResponse.statusCode)")
            }
        } catch {
            logger.debug("CDN 워밍 실패 (무시): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Stream Controls

    /// Stop the stream
    public func stopStream() async {
        await reconnectionHandler.cancel()
        playerEngine?.stop()
        await lowLatencyController?.stopSync()

        await pdtProvider?.stop()
        pdtProvider = nil

        if _isProxyActive {
            streamProxy.stop()
            _isProxyActive = false
        }

        _masterPlaylist = nil
        _currentQuality = nil
        _streamURL = nil
        _startTime = nil
        _preferredQualityVariant = nil
        _isQualityDegraded = false
        _qualityRecoveryTask?.cancel()
        _qualityRecoveryTask = nil
        _qualityProbeTask?.cancel()
        _qualityProbeTask = nil
        _userSelectedVariant = nil  // [Fix 27] 사용자 화질 잠금 해제
        _manifestRefreshTask?.cancel()
        _manifestRefreshTask = nil
        _currentVariantURL = nil
        _watchdogTask?.cancel()
        _watchdogTask = nil
        _stallCount = 0
        _lastWatchdogTime = -1
        _lastWatchdogDecodedFrames = -1
        _lastReconnectTime = .distantPast

        updatePhase(.idle)
        emitEvent(.stopped)

        logger.info("Stream stopped")
    }

    /// Pause playback
    public func pause() {
        playerEngine?.pause()
        updatePhase(.paused)
    }

    /// Resume playback
    public func resume() {
        playerEngine?.resume()
        updatePhase(.playing)
    }

    /// 백그라운드 복귀 시 재생 상태 점검 및 복구
    public func recoverFromBackground() {
        guard _phase == .playing || _phase == .buffering else { return }
        guard let engine = playerEngine else { return }

        if engine.isInErrorState {
            triggerReconnect(reason: "background recovery: engine in error state")
        } else if !engine.isPlaying {
            engine.resume()
            _stallCount = 0
            _lastWatchdogTime = -1
            _lastWatchdogDecodedFrames = -1
            Task { [weak self] in
                await self?.refreshMasterManifest()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                if !engine.isPlaying && !engine.isInErrorState {
                    await self.triggerReconnect(reason: "background recovery: resume failed after 3s")
                }
            }
        } else {
            _stallCount = 0
            _lastWatchdogTime = -1
            _lastWatchdogDecodedFrames = -1
            Task { [weak self] in
                await self?.refreshMasterManifest()
            }
        }
    }

    /// Switch quality manually
    public func switchQuality(to variant: MasterPlaylist.Variant) async throws {
        guard let engine = playerEngine else { return }

        let playURL = _isProxyActive ? streamProxy.proxyURL(from: variant.uri) : variant.uri

        // [Fix 28] 재연결/매니페스트 갱신 시 사용자가 선택한 화질을 유지하도록
        // 현재 variant URL과 preferred variant를 모두 갱신한다.
        // 기존: switchQuality 이후에도 _currentVariantURL은 최초 1080p URL을 유지 →
        // 네트워크 블립·워치독 등으로 재연결되면 사용자가 선택한 720p 등이 날아감.
        _currentVariantURL = variant.uri
        _preferredQualityVariant = variant

        try await engine.play(url: playURL)

        _currentQuality = qualityFromVariant(variant)

        emitEvent(.qualityChanged(_currentQuality!))
        logger.info("Quality switched to \(variant.qualityLabel)")
    }

    /// Get current snapshot
    public func snapshot() async -> StreamSnapshot {
        return StreamSnapshot(
            phase: _phase,
            quality: _currentQuality,
            latency: nil,
            bufferHealth: nil,
            playbackRate: Double(playerEngine?.rate ?? 1.0),
            uptime: uptime,
            timestamp: Date()
        )
    }

    // MARK: - Stream Proxy Mode Resolution

    /// 사용자 선택 모드를 현재 (엔진 × URL) 조합에 맞게 보정한다.
    /// - 호환되지 않는 조합(예: VLC 엔진 + .avInterceptor)은 안전한 기본값(.localProxy)으로 폴백.
    /// - chzzk CDN 이 아닌 URL 이면 .none 으로 폴백 (교정 불필요).
    static func resolveProxyMode(
        requested: StreamProxyMode,
        isVLC: Bool,
        isAV: Bool,
        url: URL
    ) -> StreamProxyMode {
        // chzzk CDN 이 아니면 어떤 모드든 사실상 의미 없음 → .none
        if !LocalStreamProxy.needsProxy(for: url) {
            return .none
        }

        switch requested {
        case .localProxy, .none:
            return requested

        case .urlProtocolHook:
            // 글로벌 URLProtocol 만으로는 미디어 재생 보정 불가 → 안전망으로 localProxy 동시 사용
            // (등록은 진행하되 실제 재생은 프록시 경유)
            return .localProxy

        case .avInterceptor:
            return isAV ? .avInterceptor : .localProxy

        case .directVLCAdaptive:
            return isVLC ? .directVLCAdaptive : .localProxy

        case .avAssetDownload:
            return isAV ? .avAssetDownload : .localProxy
        }
    }
}
