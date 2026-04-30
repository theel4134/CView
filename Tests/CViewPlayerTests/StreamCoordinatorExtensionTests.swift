// MARK: - StreamCoordinatorExtensionTests.swift
// CViewPlayer - StreamCoordinator 확장 메서드 (select1080p60Variant, selectInitialQuality) 테스트

import Testing
import Foundation
@testable import CViewPlayer
@testable import CViewCore

// MARK: - Test Helpers

private let baseURL = URL(string: "https://cdn.example.com/live/master.m3u8")!

private func makeVariant(
    bandwidth: Int,
    resolution: String,
    frameRate: Double? = nil,
    name: String? = nil
) -> MasterPlaylist.Variant {
    MasterPlaylist.Variant(
        bandwidth: bandwidth,
        averageBandwidth: nil,
        resolution: resolution,
        codecs: "avc1.4d401f",
        frameRate: frameRate,
        uri: baseURL.appendingPathComponent("v\(bandwidth).m3u8"),
        name: name
    )
}

private func makeCoordinator(
    preferredQuality: StreamQuality? = nil
) -> StreamCoordinator {
    StreamCoordinator(configuration: .init(
        channelId: "test",
        enableLowLatency: false,
        enableABR: false,
        preferredQuality: preferredQuality
    ))
}

private let staleVariantURL = URL(string: "https://cdn.example.com/live/chunklist_1080p.m3u8?token=stale")!

// MARK: - Reconnect URL Selection Tests

@Suite("preferredReconnectBaseURL")
struct PreferredReconnectBaseURLTests {

    @Test("AVPlayer는 stale variant 대신 master URL로 재연결")
    func avPlayerReconnectUsesMasterURL() async {
        let coordinator = makeCoordinator()

        let result = await coordinator.preferredReconnectBaseURL(
            rawURL: baseURL,
            currentVariantURL: staleVariantURL,
            keepCurrentVariant: false
        )

        #expect(result == baseURL)
    }

    @Test("VLC는 현재 variant URL을 유지해 재연결")
    func vlcReconnectKeepsVariantURL() async {
        let coordinator = makeCoordinator()

        let result = await coordinator.preferredReconnectBaseURL(
            rawURL: baseURL,
            currentVariantURL: staleVariantURL,
            keepCurrentVariant: true
        )

        #expect(result == staleVariantURL)
    }
}

// MARK: - select1080p60Variant Tests

@Suite("select1080p60Variant")
struct Select1080p60VariantTests {

    @Test("1순위: 1080p + 60fps variant 선택")
    func prioritizes1080p60fps() async {
        let coordinator = makeCoordinator()
        let variants = [
            makeVariant(bandwidth: 8_000_000, resolution: "1920x1080", frameRate: 60.0),
            makeVariant(bandwidth: 4_000_000, resolution: "1280x720", frameRate: 30.0),
            makeVariant(bandwidth: 2_000_000, resolution: "854x480"),
        ]
        let result = await coordinator.select1080p60Variant(from: variants)
        #expect(result?.resolution == "1920x1080")
        #expect(result?.frameRate == 60.0)
    }

    @Test("59fps 도 60fps 범주에 포함 (>= 59.0)")
    func includes59fps() async {
        let coordinator = makeCoordinator()
        let variants = [
            makeVariant(bandwidth: 8_000_000, resolution: "1920x1080", frameRate: 59.94),
            makeVariant(bandwidth: 4_000_000, resolution: "1280x720"),
        ]
        let result = await coordinator.select1080p60Variant(from: variants)
        #expect(result?.resolution == "1920x1080")
        #expect(result?.frameRate == 59.94)
    }

    @Test("2순위: 1080p + 30fps (60fps 없을 때)")
    func fallsBackTo1080pAnyFps() async {
        let coordinator = makeCoordinator()
        let variants = [
            makeVariant(bandwidth: 6_000_000, resolution: "1920x1080", frameRate: 30.0),
            makeVariant(bandwidth: 4_000_000, resolution: "1280x720", frameRate: 60.0),
            makeVariant(bandwidth: 2_000_000, resolution: "854x480"),
        ]
        let result = await coordinator.select1080p60Variant(from: variants)
        #expect(result?.resolution == "1920x1080")
        #expect(result?.frameRate == 30.0)
    }

    @Test("3순위: 1080p 없으면 최고 bandwidth")
    func fallsBackToHighestBandwidth() async {
        let coordinator = makeCoordinator()
        let variants = [
            makeVariant(bandwidth: 4_000_000, resolution: "1280x720", frameRate: 60.0),
            makeVariant(bandwidth: 2_000_000, resolution: "854x480"),
            makeVariant(bandwidth: 1_000_000, resolution: "640x360"),
        ]
        let result = await coordinator.select1080p60Variant(from: variants)
        #expect(result?.bandwidth == 4_000_000)
    }

    @Test("빈 배열 → nil 반환")
    func emptyVariants() async {
        let coordinator = makeCoordinator()
        let result = await coordinator.select1080p60Variant(from: [])
        #expect(result == nil)
    }

    @Test("여러 1080p60 중 bandwidth 가장 높은 것 선택")
    func highestBandwidth1080p60() async {
        let coordinator = makeCoordinator()
        let variants = [
            makeVariant(bandwidth: 6_000_000, resolution: "1920x1080", frameRate: 60.0),
            makeVariant(bandwidth: 8_000_000, resolution: "1920x1080", frameRate: 60.0),
            makeVariant(bandwidth: 4_000_000, resolution: "1280x720"),
        ]
        // sorted by bandwidth desc → 8M first
        let result = await coordinator.select1080p60Variant(from: variants)
        #expect(result?.bandwidth == 8_000_000)
    }

    @Test("1080p + frameRate nil (60fps 아님) → 2순위로 선택")
    func noFrameRateFallsToSecondPriority() async {
        let coordinator = makeCoordinator()
        let variants = [
            makeVariant(bandwidth: 6_000_000, resolution: "1920x1080", frameRate: nil),
            makeVariant(bandwidth: 4_000_000, resolution: "1280x720", frameRate: 60.0),
        ]
        let result = await coordinator.select1080p60Variant(from: variants)
        #expect(result?.resolution == "1920x1080")
        // frameRate nil이므로 1순위(60fps)가 아닌 2순위(1080p any)로 매칭
        #expect(result?.bandwidth == 6_000_000)
    }
}

// MARK: - selectInitialQuality Tests

@Suite("selectInitialQuality")
struct SelectInitialQualityTests {

    @Test("preferredQuality 설정 시 → displayName 매칭")
    func preferredQualityMatched() async {
        let coordinator = makeCoordinator(preferredQuality: .high)
        let master = MasterPlaylist(
            variants: [
                makeVariant(bandwidth: 8_000_000, resolution: "1920x1080", name: "원본 (1080p)"),
                makeVariant(bandwidth: 4_000_000, resolution: "1280x720", name: "고화질 (720p)"),
                makeVariant(bandwidth: 2_000_000, resolution: "854x480", name: "중화질 (480p)"),
            ],
            uri: baseURL
        )
        let result = await coordinator.selectInitialQuality(from: master)
        // StreamQuality.high.displayName == "고화질 (720p)" → name 매칭
        #expect(result.resolution == "1280x720")
    }

    @Test("preferredQuality 매칭 실패 → 중간 인덱스 반환")
    func preferredQualityNotMatched() async {
        let coordinator = makeCoordinator(preferredQuality: .low) // "저화질 (360p)"
        let master = MasterPlaylist(
            variants: [
                makeVariant(bandwidth: 8_000_000, resolution: "1920x1080"),
                makeVariant(bandwidth: 4_000_000, resolution: "1280x720"),
                makeVariant(bandwidth: 2_000_000, resolution: "854x480"),
            ],
            uri: baseURL
        )
        let result = await coordinator.selectInitialQuality(from: master)
        // 매칭 실패 → variants[3/2] = variants[1]
        #expect(result.resolution == "1280x720")
    }

    @Test("preferredQuality nil → 중간 인덱스 선택")
    func noPreferredQuality() async {
        let coordinator = makeCoordinator(preferredQuality: nil)
        let master = MasterPlaylist(
            variants: [
                makeVariant(bandwidth: 8_000_000, resolution: "1920x1080"),
                makeVariant(bandwidth: 4_000_000, resolution: "1280x720"),
                makeVariant(bandwidth: 2_000_000, resolution: "854x480"),
                makeVariant(bandwidth: 1_000_000, resolution: "640x360"),
            ],
            uri: baseURL
        )
        let result = await coordinator.selectInitialQuality(from: master)
        // variants[4/2] = variants[2]
        #expect(result.resolution == "854x480")
    }

    @Test("variant 1개 → 유일한 variant 반환")
    func singleVariant() async {
        let coordinator = makeCoordinator()
        let master = MasterPlaylist(
            variants: [
                makeVariant(bandwidth: 4_000_000, resolution: "1280x720"),
            ],
            uri: baseURL
        )
        let result = await coordinator.selectInitialQuality(from: master)
        #expect(result.resolution == "1280x720")
    }
}

// MARK: - Variant qualityLabel Tests

@Suite("Variant qualityLabel")
struct VariantQualityLabelTests {

    @Test("name 있으면 그대로 반환")
    func nameReturned() {
        let variant = makeVariant(bandwidth: 8_000_000, resolution: "1920x1080", name: "원본 (1080p)")
        #expect(variant.qualityLabel == "원본 (1080p)")
    }

    @Test("name nil + 1080p → '1080p'")
    func resolution1080p() {
        let variant = makeVariant(bandwidth: 8_000_000, resolution: "1920x1080")
        #expect(variant.qualityLabel == "1080p")
    }

    @Test("name nil + 720p → '720p'")
    func resolution720p() {
        let variant = makeVariant(bandwidth: 4_000_000, resolution: "1280x720")
        #expect(variant.qualityLabel == "720p")
    }

    @Test("name nil + 480p → '480p'")
    func resolution480p() {
        let variant = makeVariant(bandwidth: 2_000_000, resolution: "854x480")
        #expect(variant.qualityLabel == "480p")
    }

    @Test("name nil + 360p → '360p'")
    func resolution360p() {
        let variant = makeVariant(bandwidth: 1_000_000, resolution: "640x360")
        #expect(variant.qualityLabel == "360p")
    }

    @Test("name nil + 비표준 해상도 → bandwidth kbps")
    func unknownResolution() {
        let variant = makeVariant(bandwidth: 3_500_000, resolution: "2560x1440")
        #expect(variant.qualityLabel == "3500kbps")
    }
}

// MARK: - StreamRecordingService Tests

@Suite("StreamRecordingService.defaultRecordingURL")
struct StreamRecordingServiceTests {

    @Test("영문 채널명 → 그대로 유지")
    func englishChannelName() {
        let url = StreamRecordingService.defaultRecordingURL(channelName: "TestChannel")
        let filename = url.lastPathComponent
        #expect(filename.hasPrefix("TestChannel_"))
        #expect(filename.hasSuffix(".ts"))
    }

    @Test("한글 채널명 → 유지 (한글 허용)")
    func koreanChannelName() {
        let url = StreamRecordingService.defaultRecordingURL(channelName: "테스트채널")
        let filename = url.lastPathComponent
        #expect(filename.hasPrefix("테스트채널_"))
        #expect(filename.hasSuffix(".ts"))
    }

    @Test("특수문자 → 밑줄로 치환")
    func specialCharsReplaced() {
        let url = StreamRecordingService.defaultRecordingURL(channelName: "test@#$%channel!")
        let filename = url.lastPathComponent
        // 특수문자들이 _ 로 치환되었는지 확인
        #expect(!filename.contains("@"))
        #expect(!filename.contains("#"))
        #expect(!filename.contains("!"))
        #expect(filename.hasPrefix("test"))
        #expect(filename.hasSuffix(".ts"))
    }

    @Test("공백 → 밑줄로 치환")
    func spacesReplaced() {
        let url = StreamRecordingService.defaultRecordingURL(channelName: "test channel")
        let filename = url.lastPathComponent
        #expect(filename.contains("test_channel"))
    }

    @Test("저장 디렉토리 == Movies/CView")
    func directoryIsCView() {
        let url = StreamRecordingService.defaultRecordingURL(channelName: "test")
        let dir = url.deletingLastPathComponent().lastPathComponent
        #expect(dir == "CView")
    }

    @Test("RecordingState idle Equatable")
    func recordingStateEquatable() async {
        let service = StreamRecordingService()
        let state = await service.currentState
        #expect(state == .idle)
    }

    @Test("RecordingState enum 값 비교")
    func recordingStateValues() {
        #expect(RecordingState.idle == RecordingState.idle)
        #expect(RecordingState.recording == RecordingState.recording)
        #expect(RecordingState.stopping == RecordingState.stopping)
        #expect(RecordingState.error("a") == RecordingState.error("a"))
        #expect(RecordingState.error("a") != RecordingState.error("b"))
        #expect(RecordingState.idle != RecordingState.recording)
    }
}
