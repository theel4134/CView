// MARK: - MetricsSettingsTests.swift
// CViewCore MetricsSettings 정규화 테스트

import Testing
import Foundation
@testable import CViewCore

@Suite("MetricsSettings")
struct MetricsSettingsTests {

    @Test("init에서 주기값을 안전 범위로 정규화")
    func intervalClampOnInit() {
        let settings = MetricsSettings(
            metricsEnabled: true,
            serverURL: "https://cv.dododo.app",
            forwardInterval: 0.1,
            pingInterval: 9999
        )

        #expect(settings.forwardInterval == MetricsSettings.minForwardInterval)
        #expect(settings.pingInterval == MetricsSettings.maxPingInterval)
    }

    @Test("serverURL 공백/스킴 누락 정규화")
    func serverURLNormalization() {
        let withBlank = MetricsSettings(serverURL: "   ")
        #expect(withBlank.serverURL == MetricsSettings.defaultServerURL)

        let withoutScheme = MetricsSettings(serverURL: "cv.dododo.app")
        #expect(withoutScheme.serverURL == "https://cv.dododo.app")
    }

    @Test("decode 시에도 정규화 적용")
    func decodeNormalization() throws {
        let raw = """
        {
          "metricsEnabled": true,
          "serverURL": "cv.dododo.app",
          "forwardInterval": -10,
          "pingInterval": 99999
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MetricsSettings.self, from: raw)

        #expect(decoded.metricsEnabled == true)
        #expect(decoded.serverURL == "https://cv.dododo.app")
        #expect(decoded.forwardInterval == MetricsSettings.minForwardInterval)
        #expect(decoded.pingInterval == MetricsSettings.maxPingInterval)
    }
}
