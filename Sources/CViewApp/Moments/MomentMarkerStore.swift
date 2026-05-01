// MARK: - MomentMarkerStore.swift
// 라이브 시청 중 순간 마커 저장/복원.
// 채널별로 최대 500개를 UserDefaults에 JSON으로 저장한다.
// [Plan 2026-04-30 MOM-1]

import Foundation

// MARK: - MomentMarker

struct MomentMarker: Codable, Identifiable, Sendable {
    var id: UUID = .init()
    var channelId: String
    var channelName: String
    var createdAt: Date = .init()
    var programDateTime: Date?
    var appLatencyMs: Double?
    var webDriftMs: Double?
    var playbackRate: Double = 1.0
    var qualityLabel: String?
    var note: String?
    var recordingURL: URL?
}

// MARK: - MomentMarkerStore (actor-isolated, UserDefaults-backed)

@MainActor
final class MomentMarkerStore: ObservableObject {

    static let shared = MomentMarkerStore()

    private let defaultsKey = "MomentMarkers.v1"
    private let capacity = 500
    private(set) var markers: [MomentMarker] = []

    init() { load() }

    // MARK: Public API

    func add(_ marker: MomentMarker) {
        markers.append(marker)
        if markers.count > capacity { markers.removeFirst(markers.count - capacity) }
        save()
    }

    func remove(id: UUID) {
        markers.removeAll { $0.id == id }
        save()
    }

    func markers(for channelId: String) -> [MomentMarker] {
        markers.filter { $0.channelId == channelId }.sorted { $0.createdAt > $1.createdAt }
    }

    func clearAll(for channelId: String) {
        markers.removeAll { $0.channelId == channelId }
        save()
    }

    /// JSON export string for all markers
    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(markers)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([MomentMarker].self, from: data)
        else { return }
        markers = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(markers) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
