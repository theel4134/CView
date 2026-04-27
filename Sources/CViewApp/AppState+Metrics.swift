// MARK: - AppState+Metrics.swift
// AppState의 메트릭 설정/테스트 책임 분리 (Refactor P1-5)
//
// 분리 이유:
// - AppState 본체에서 메트릭 도메인 로직 격리
// - 동일 모듈 내 extension이므로 internal 멤버 접근 가능

import Foundation
import CViewCore

@MainActor
extension AppState {

    // MARK: - Metrics

    /// 메트릭 서버 연결 테스트 (설정된 URL 기준)
    func testMetricsConnection() async -> (success: Bool, latencyMs: Double, message: String) {
        guard let client = metricsClient else {
            return (false, 0, "메트릭 클라이언트가 초기화되지 않았습니다")
        }
        // 최신 URL 반영
        if let url = URL(string: settingsStore.metrics.serverURL), !settingsStore.metrics.serverURL.isEmpty {
            await client.updateBaseURL(url)
        }
        return await client.testConnection()
    }

    /// 메트릭 설정을 MetricsAPIClient · MetricsForwarder에 적용
    /// DataStore 로드 완료 후, 또는 사용자가 설정을 변경할 때 호출
    func applyMetricsSettings() async {
        let normalized = settingsStore.metrics.normalized()
        if normalized != settingsStore.metrics {
            settingsStore.metrics = normalized
        }

        let ms = normalized
        let forwardInterval = MetricsSettings.clampForwardInterval(ms.forwardInterval)
        let pingInterval = MetricsSettings.clampPingInterval(ms.pingInterval)

        // 서버 URL 업데이트
        if let url = URL(string: ms.serverURL), !ms.serverURL.isEmpty {
            await metricsClient?.updateBaseURL(url)
        }

        // 전송 주기 업데이트
        await metricsForwarder?.updateIntervals(
            forward: forwardInterval,
            ping: pingInterval
        )

        // 활성화/비활성화 (setEnabled가 내부에서 상태 변화 감지)
        await metricsForwarder?.setEnabled(ms.metricsEnabled)

        logger.info("Metrics settings applied – enabled: \(ms.metricsEnabled), url: \(ms.serverURL, privacy: .private), intervals: fwd=\(forwardInterval, privacy: .public)s ping=\(pingInterval, privacy: .public)s")
    }
}
