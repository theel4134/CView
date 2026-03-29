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

            // [Fix 16] VLC + AVPlayer 모두 프록시 경유
            // CDN이 fMP4 세그먼트를 Content-Type: video/MP2T로 잘못 응답
            // → 프록시에서 video/mp4로 교정하여 VLC MP4→TS 전환 버그 방지
            // Fix 15 회귀(프록시 과부하) 대응: M3U8 응답 1초 캐싱으로 VLC 폴링 부하 해소
            if LocalStreamProxy.needsProxy(for: url) {
                if let host = url.host {
                    var proxyStarted = false
                    do {
                        try await streamProxy.start(for: host)
                        proxyStarted = true
                        _isProxyActive = true
                        streamProxy.onUpstreamAuthFailure = { [weak self] in
                            Task { [weak self] in
                                await self?.triggerReconnect(reason: "CDN 403 토큰 만료 감지")
                            }
                        }
                        let engineLabel = isVLCEngine ? "VLC" : "AVPlayer"
                        logger.info("CDN proxy active (\(engineLabel, privacy: .public)): \(host, privacy: .public) → localhost:\(self.streamProxy.port, privacy: .public)")
                    } catch {
                        logger.warning("CDN proxy failed: \(error.localizedDescription, privacy: .public)")
                    }
                    if !proxyStarted {
                        logger.warning("CDN proxy failed, direct connection fallback")
                    }
                }
            }

            if isVLCEngine {
                // [Fix 16g] VLC에 chunklist(미디어 플레이리스트) URL 직접 전달
                _currentVariantURL = url  // 원본 CDN URL 보존 (재연결용)

                // [Opt: Single VLC] 프리페치 매니페스트가 있으면 네트워크 재요청 생략
                if let prefetchedMaster = _masterPlaylist, !prefetchedMaster.variants.isEmpty {
                    let sortedVariants = prefetchedMaster.variants.sorted { $0.bandwidth > $1.bandwidth }
                    let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                        ?? sortedVariants.first

                    // ABR 레벨 설정 (프리페치 경로에서도 필요)
                    await abrController?.setLevels(prefetchedMaster.variants)

                    // CDN 워밍만 비동기 실행 (variant 해석은 이미 완료)
                    await warmUpCDNConnection(url: url)

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
                // AVPlayer: 마스터 URL을 프록시 경유로 전달 (AVPlayer 내장 ABR 활용)
                if let prefetchedMaster = _masterPlaylist, !prefetchedMaster.variants.isEmpty {
                    await resolveAVPlayerInitialQuality(from: prefetchedMaster)
                } else {
                    await resolveAVPlayerManifest(from: url)
                }

                if _isProxyActive {
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

            // 매니페스트 주기적 갱신 타이머 시작 (VLC 토큰 리프레시 + variant URL 갱신)
            if isVLCEngine {
                startManifestRefreshTimer()
            }

            // 저지연 싱크: 백그라운드에서 비동기 실행
            if config.enableLowLatency {
                Task { [weak self] in await self?.startLowLatencySync() }
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
}
