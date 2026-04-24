// StreamCoordinator+ManifestRefresh.swift
// CView_v2 — Manifest Refresh Timer (Token Refresh + Variant URL Update)

import Foundation
import CViewCore

// MARK: - Manifest Refresh Timer (Token Refresh + Variant URL Update)

extension StreamCoordinator {

    /// 매니페스트 주기적 갱신 타이머 시작 (프로파일별 갱신 주기)
    /// 치지직 CDN URL의 토큰/서명이 만료되면 variant URL이 무효화되므로
    /// 주기적으로 마스터 매니페스트를 재파싱하여 신선한 variant URL을 유지합니다.
    /// lowLatency=15초, normal=20초, highBuffer=30초 주기
    func startManifestRefreshTimer() {
        _manifestRefreshTask?.cancel()
        
        // 프로파일에서 갱신 주기 취득 (actor-isolated 컨텍스트에서 미리 읽기)
        let refreshInterval: Int
        if let vlcEngine = self.playerEngine as? VLCPlayerEngine {
            refreshInterval = vlcEngine.streamingProfile.manifestRefreshInterval
        } else {
            refreshInterval = 20  // 기본 20초
        }
        // [P1-5 2026-04-24] session별 stagger — 채널마다 결정적 오프셋을 부여하여
        //   다중 멀티라이브 세션이 동일 시점에 매니페스트를 fetch 하지 않도록 분산.
        let channelHash = UInt(bitPattern: self.config.channelId.hashValue)
        let staggerSlots = max(1, UInt(refreshInterval) * 250)  // 0..(refreshInterval*250)ms
        let staggerMs = Int(channelHash % staggerSlots)

        _manifestRefreshTask = Task { [weak self] in
            // 초기 대기 (최초 재생 직후에는 굳이 갱신 필요 없음) + stagger
            do { try await Task.sleep(for: .seconds(refreshInterval)) } catch { return }
            if staggerMs > 0 {
                do { try await Task.sleep(for: .milliseconds(staggerMs)) } catch { return }
            }

            while !Task.isCancelled {
                guard let self else { break }
                await self.refreshMasterManifest()
                do { try await Task.sleep(for: .seconds(refreshInterval)) } catch { return }
            }
        }
    }

    /// 마스터 매니페스트를 다시 다운로드하여 variant URL을 갱신합니다.
    /// 토큰 리프레시 + variant 목록 업데이트 + VLC 엔진 URL 동기화.
    func refreshMasterManifest() async {
        guard let streamURL = _streamURL else { return }
        // 에러/재연결 중에는 주기적 갱신 사이클 스킵 (호출자가 triggerReconnect인 경우는 예외)
        // triggerReconnect에서 직접 호출 시에는 .reconnecting 상태이므로 phase 체크는 .error만
        if case .error = _phase {
            return
        }
        
        do {
            var request = URLRequest(url: streamURL)
            request.timeoutInterval = 5
            request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            request.cachePolicy = .reloadIgnoringLocalCacheData  // 캐시 무시
            
            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            guard content.contains("#EXT-X-STREAM-INF") else { return }
            
            let master = try await hlsParser.parseMasterPlaylist(content: content, baseURL: streamURL)
            
            // 매니페스트 업데이트
            _masterPlaylist = master
            _manifestRefreshFailCount = 0  // 성공 시 실패 카운터 리셋
            await abrController?.setLevels(master.variants)

            // [Fix 28] 사용자가 수동으로 화질을 고정한 상태면 해당 화질의 최신 URL로 갱신
            // 기존: refreshMasterManifest가 항상 1080p variant로 _currentVariantURL과
            // _currentQuality를 덮어써 사용자 선택이 무효화되고 재연결 시 1080p로 강제 복귀.
            if let userVariant = _userSelectedVariant,
               let freshVariant = master.variants.first(where: { $0.bandwidth == userVariant.bandwidth }) {
                _userSelectedVariant = freshVariant
                _preferredQualityVariant = freshVariant
                _currentVariantURL = freshVariant.uri
                _currentQuality = qualityFromVariant(freshVariant)
                logger.debug("매니페스트 갱신: 사용자 선택 화질(\(freshVariant.qualityLabel)) URL 동기화")
                return
            }

            // 1080p variant URL 갱신
            let sortedVariants = master.variants.sorted { $0.bandwidth > $1.bandwidth }
            let target = sortedVariants.first(where: { $0.resolution.contains("1080") })
                ?? sortedVariants.first
            
            if let variant = target {
                let newURL = variant.uri
                let oldURL = _currentVariantURL
                _currentVariantURL = newURL
                
                // [Fix 26] 화질 저하 상태에서는 _currentQuality를 덮어쓰지 않음
                // — VLC가 실제 재생 중인 저화질과 UI 표시가 불일치하는 문제 방지
                // — _preferredQualityVariant만 갱신하여 복귀 시 최신 URL 사용
                if _isQualityDegraded {
                    _preferredQualityVariant = variant
                    logger.debug("매니페스트 갱신: 화질 저하 상태 — preferredVariant URL만 갱신 (currentQuality 유지)")
                } else {
                    _preferredQualityVariant = variant
                    _currentQuality = qualityFromVariant(variant)
                }

                if oldURL != newURL {
                    logger.info("매니페스트 갱신: variant URL 변경됨 (토큰 리프레시)")
                } else {
                    logger.debug("매니페스트 갱신: variant URL 동일 (토큰 유효)")
                }
            }
        } catch {
            self._manifestRefreshFailCount += 1
            if self._manifestRefreshFailCount >= 5 {
                self.logger.warning("매니페스트 갱신 \(self._manifestRefreshFailCount)회 연속 실패 — 재연결 시도")
                self._manifestRefreshFailCount = 0
                self.triggerReconnect(reason: "manifest refresh 5회 연속 실패")
            } else {
                self.logger.debug("매니페스트 갱신 실패 (\(self._manifestRefreshFailCount)/5): \(error.localizedDescription)")
            }
        }
    }

    /// 백그라운드에서 매니페스트를 파싱하여 품질 정보 수집 (재생에는 영향 없음)
    func loadManifestInfo(from url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: url)
                request.setValue(CommonHeaders.safariUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
                
                let (data, _) = try await hlsSession.data(for: request)
                let content = String(data: data, encoding: .utf8) ?? ""
                
                if content.contains("#EXT-X-STREAM-INF") {
                    let master = try await self.hlsParser.parseMasterPlaylist(content: content, baseURL: url)
                    await self.updateMasterPlaylist(master)
                }
            } catch {
                await self.logger.debug("Manifest info fetch skipped: \(error.localizedDescription)")
            }
        }
    }
    
    /// 매니페스트 정보 업데이트 (actor-isolated)
    func updateMasterPlaylist(_ master: MasterPlaylist) async {
        _masterPlaylist = master
        await abrController?.setLevels(master.variants)
        
        // [Phase 4] 1080p 60fps variant를 현재 품질로 표시
        if let best = select1080p60Variant(from: master.variants) {
            _currentQuality = qualityFromVariant(best)
            emitEvent(.qualitySelected(_currentQuality!))
        }
    }
}
