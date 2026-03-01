// MARK: - HLSManifestParser.swift
// CViewPlayer - HLS M3U8 manifest parser
// 원본: HLS.js port → 개선: Swift-native Sendable parser

import Foundation
import CViewCore

// MARK: - HLS Manifest Models

public struct MasterPlaylist: Sendable, Equatable {
    public let variants: [Variant]
    public let uri: URL
    
    public struct Variant: Sendable, Equatable, Identifiable {
        public var id: String { "\(bandwidth)-\(resolution)" }
        public let bandwidth: Int
        public let averageBandwidth: Int?
        public let resolution: String
        public let codecs: String?
        public let frameRate: Double?
        public let uri: URL
        public let name: String?
        
        /// Display-friendly quality label
        public var qualityLabel: String {
            if let name { return name }
            if resolution.contains("1080") { return "1080p" }
            if resolution.contains("720") { return "720p" }
            if resolution.contains("480") { return "480p" }
            if resolution.contains("360") { return "360p" }
            return "\(bandwidth / 1000)kbps"
        }
    }
}

public struct MediaPlaylist: Sendable {
    public let targetDuration: Double
    public let mediaSequence: Int
    public let partTargetDuration: Double?
    public let segments: [Segment]
    public let partialSegments: [PartialSegment]
    public let serverControl: ServerControl?
    public let preloadHint: PreloadHint?
    public let isEndList: Bool
    public let isLowLatency: Bool
    
    public var totalDuration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }
    
    /// The last segment's end time
    public var endTime: Double {
        guard let last = segments.last else { return 0 }
        return last.startTime + last.duration
    }
    
    public struct Segment: Sendable, Identifiable {
        public let id: Int // sequence number
        public let duration: Double
        public let uri: URL
        public let startTime: Double
        public let programDateTime: Date?
        public let discontinuity: Bool
        public let byteRange: ByteRange?
        public let parts: [PartialSegment]
    }
    
    public struct PartialSegment: Sendable, Identifiable {
        public let id: String
        public let duration: Double
        public let uri: URL
        public let independent: Bool
        public let byteRange: ByteRange?
        public let gap: Bool
    }
    
    public struct ByteRange: Sendable {
        public let length: Int
        public let offset: Int?
    }
    
    public struct ServerControl: Sendable {
        public let canSkipUntil: Double?
        public let canBlockReload: Bool
        public let holdBack: Double?
        public let partHoldBack: Double?
    }
    
    public struct PreloadHint: Sendable {
        public let type: String
        public let uri: URL
        public let byteRangeStart: Int?
        public let byteRangeLength: Int?
    }
}

// MARK: - HLS Manifest Parser

/// Parses HLS M3U8 manifests (both master and media playlists).
/// Supports Low-Latency HLS (LL-HLS) extensions.
/// Pure struct, Sendable & thread-safe.
public struct HLSManifestParser: Sendable {
    
    private let logger = AppLogger.hls
    
    public init() {}
    
    // MARK: - Master Playlist
    
    /// Parse a master playlist from M3U8 content
    public func parseMasterPlaylist(content: String, baseURL: URL) throws -> MasterPlaylist {
        let lines = content.components(separatedBy: .newlines)
        
        guard lines.first?.hasPrefix("#EXTM3U") == true else {
            throw AppError.player(.invalidManifest)
        }
        
        var variants: [MasterPlaylist.Variant] = []
        var currentAttributes: [String: String] = [:]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                let attrString = String(trimmed.dropFirst("#EXT-X-STREAM-INF:".count))
                currentAttributes = parseAttributes(attrString)
                
            } else if !trimmed.hasPrefix("#") && !trimmed.isEmpty && !currentAttributes.isEmpty {
                let uri = resolveURL(trimmed, base: baseURL)
                
                let variant = MasterPlaylist.Variant(
                    bandwidth: Int(currentAttributes["BANDWIDTH"] ?? "0") ?? 0,
                    averageBandwidth: Int(currentAttributes["AVERAGE-BANDWIDTH"] ?? ""),
                    resolution: currentAttributes["RESOLUTION"] ?? "",
                    codecs: currentAttributes["CODECS"],
                    frameRate: Double(currentAttributes["FRAME-RATE"] ?? ""),
                    uri: uri,
                    name: currentAttributes["NAME"]
                )
                
                variants.append(variant)
                currentAttributes = [:]
            }
        }
        
        // 빈 variants → 유효하지 않은 매니페스트
        guard !variants.isEmpty else {
            throw AppError.player(.invalidManifest)
        }
        
        // Sort by bandwidth descending
        let sorted = variants.sorted { $0.bandwidth > $1.bandwidth }
        return MasterPlaylist(variants: sorted, uri: baseURL)
    }
    
    // MARK: - Media Playlist
    
    /// Parse a media playlist from M3U8 content
    public func parseMediaPlaylist(content: String, baseURL: URL) throws -> MediaPlaylist {
        let lines = content.components(separatedBy: .newlines)
        
        guard lines.first?.hasPrefix("#EXTM3U") == true else {
            throw AppError.player(.invalidManifest)
        }
        
        var targetDuration: Double = 0
        var mediaSequence = 0
        var partTargetDuration: Double?
        var segments: [MediaPlaylist.Segment] = []
        var partialSegments: [MediaPlaylist.PartialSegment] = []
        var serverControl: MediaPlaylist.ServerControl?
        var preloadHint: MediaPlaylist.PreloadHint?
        var isEndList = false
        var isLowLatency = false
        
        // Current segment parsing state
        var currentDuration: Double = 0
        var currentPDT: Date?
        var currentDiscontinuity = false
        var currentByteRange: MediaPlaylist.ByteRange?
        var currentParts: [MediaPlaylist.PartialSegment] = []
        var currentTime: Double = 0
        var segmentIndex = mediaSequence
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = Double(trimmed.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 0
                
            } else if trimmed.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                mediaSequence = Int(trimmed.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
                segmentIndex = mediaSequence
                
            } else if trimmed.hasPrefix("#EXTINF:") {
                let durationStr = String(trimmed.dropFirst("#EXTINF:".count))
                    .components(separatedBy: ",").first ?? "0"
                currentDuration = Double(durationStr) ?? 0
                
            } else if trimmed.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                let dateStr = String(trimmed.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count))
                let fmtFrac = ISO8601DateFormatter()
                fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fmtPlain = ISO8601DateFormatter()
                fmtPlain.formatOptions = [.withInternetDateTime]
                currentPDT = fmtFrac.date(from: dateStr) ?? fmtPlain.date(from: dateStr)
                
            } else if trimmed == "#EXT-X-DISCONTINUITY" {
                currentDiscontinuity = true
                
            } else if trimmed.hasPrefix("#EXT-X-BYTERANGE:") {
                currentByteRange = parseByteRange(String(trimmed.dropFirst("#EXT-X-BYTERANGE:".count)))
                
            } else if trimmed.hasPrefix("#EXT-X-PART-INF:") {
                let attrs = parseAttributes(String(trimmed.dropFirst("#EXT-X-PART-INF:".count)))
                partTargetDuration = Double(attrs["PART-TARGET"] ?? "")
                isLowLatency = true
                
            } else if trimmed.hasPrefix("#EXT-X-PART:") {
                let attrs = parseAttributes(String(trimmed.dropFirst("#EXT-X-PART:".count)))
                if let uriStr = attrs["URI"] {
                    let part = MediaPlaylist.PartialSegment(
                        id: "\(segmentIndex)-\(currentParts.count)",
                        duration: Double(attrs["DURATION"] ?? "0") ?? 0,
                        uri: resolveURL(uriStr, base: baseURL),
                        independent: attrs["INDEPENDENT"]?.uppercased() == "YES",
                        byteRange: attrs["BYTERANGE"].flatMap { parseByteRange($0) },
                        gap: attrs["GAP"]?.uppercased() == "YES"
                    )
                    currentParts.append(part)
                    partialSegments.append(part)
                }
                isLowLatency = true
                
            } else if trimmed.hasPrefix("#EXT-X-SERVER-CONTROL:") {
                let attrs = parseAttributes(String(trimmed.dropFirst("#EXT-X-SERVER-CONTROL:".count)))
                serverControl = MediaPlaylist.ServerControl(
                    canSkipUntil: Double(attrs["CAN-SKIP-UNTIL"] ?? ""),
                    canBlockReload: attrs["CAN-BLOCK-RELOAD"]?.uppercased() == "YES",
                    holdBack: Double(attrs["HOLD-BACK"] ?? ""),
                    partHoldBack: Double(attrs["PART-HOLD-BACK"] ?? "")
                )
                
            } else if trimmed.hasPrefix("#EXT-X-PRELOAD-HINT:") {
                let attrs = parseAttributes(String(trimmed.dropFirst("#EXT-X-PRELOAD-HINT:".count)))
                if let uriStr = attrs["URI"] {
                    preloadHint = MediaPlaylist.PreloadHint(
                        type: attrs["TYPE"] ?? "PART",
                        uri: resolveURL(uriStr, base: baseURL),
                        byteRangeStart: Int(attrs["BYTERANGE-START"] ?? ""),
                        byteRangeLength: Int(attrs["BYTERANGE-LENGTH"] ?? "")
                    )
                }
                
            } else if trimmed == "#EXT-X-ENDLIST" {
                isEndList = true
                
            } else if !trimmed.hasPrefix("#") && !trimmed.isEmpty {
                // Segment URI
                let segment = MediaPlaylist.Segment(
                    id: segmentIndex,
                    duration: currentDuration,
                    uri: resolveURL(trimmed, base: baseURL),
                    startTime: currentTime,
                    programDateTime: currentPDT,
                    discontinuity: currentDiscontinuity,
                    byteRange: currentByteRange,
                    parts: currentParts
                )
                
                segments.append(segment)
                currentTime += currentDuration
                segmentIndex += 1
                
                // Reset
                currentDuration = 0
                currentPDT = nil
                currentDiscontinuity = false
                currentByteRange = nil
                currentParts = []
            }
        }
        
        return MediaPlaylist(
            targetDuration: targetDuration,
            mediaSequence: mediaSequence,
            partTargetDuration: partTargetDuration,
            segments: segments,
            partialSegments: partialSegments,
            serverControl: serverControl,
            preloadHint: preloadHint,
            isEndList: isEndList,
            isLowLatency: isLowLatency
        )
    }
    
    // MARK: - Helpers
    
    /// Parse M3U8 attribute string into dictionary
    private func parseAttributes(_ input: String) -> [String: String] {
        var result: [String: String] = [:]
        var remaining = input[input.startIndex...]
        
        while !remaining.isEmpty {
            // Find key
            guard let eqIdx = remaining.firstIndex(of: "=") else { break }
            let key = String(remaining[remaining.startIndex..<eqIdx])
                .trimmingCharacters(in: .whitespaces)
            remaining = remaining[remaining.index(after: eqIdx)...]
            
            let value: String
            if remaining.first == "\"" {
                // Quoted value
                remaining = remaining.dropFirst()
                if let endQuote = remaining.firstIndex(of: "\"") {
                    value = String(remaining[remaining.startIndex..<endQuote])
                    remaining = remaining[remaining.index(after: endQuote)...]
                } else {
                    value = String(remaining)
                    remaining = remaining[remaining.endIndex...]
                }
            } else {
                // Unquoted value
                if let commaIdx = remaining.firstIndex(of: ",") {
                    value = String(remaining[remaining.startIndex..<commaIdx])
                    remaining = remaining[remaining.index(after: commaIdx)...]
                } else {
                    value = String(remaining).trimmingCharacters(in: .whitespaces)
                    remaining = remaining[remaining.endIndex...]
                }
            }
            
            result[key] = value
            
            // Skip comma
            if remaining.first == "," {
                remaining = remaining.dropFirst()
            }
        }
        
        return result
    }
    
    private func resolveURL(_ path: String, base: URL) -> URL {
        let cleaned = path.trimmingCharacters(in: .init(charactersIn: "\""))
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            return URL(string: cleaned) ?? base
        }
        // [Fix] appendingPathComponent()는 파일시스템 API로서 percent-encoding을 재적용한다.
        // Chzzk CDN의 Akamai 토큰 경로에 포함된 %2F가 %252F로 이중 인코딩되면
        // CDN이 HTTP 400을 반환하여 VLC가 OPENING → ERROR 즉시 전환된다.
        //
        // URL(string:relativeTo:)는 RFC 3986에 따라 기존 percent-encoding을 보존하므로
        // 이중 인코딩 없이 올바른 URL을 생성한다.
        let baseDir = base.deletingLastPathComponent()
        if let resolved = URL(string: cleaned, relativeTo: baseDir) {
            return resolved.absoluteURL
        }
        return baseDir.appendingPathComponent(cleaned)  // 최후 폴백
    }
    
    private func parseByteRange(_ input: String) -> MediaPlaylist.ByteRange? {
        let parts = input.split(separator: "@")
        guard let length = Int(parts[0]) else { return nil }
        let offset = parts.count > 1 ? Int(parts[1]) : nil
        return MediaPlaylist.ByteRange(length: length, offset: offset)
    }
}
