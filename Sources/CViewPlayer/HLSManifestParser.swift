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

    // flashls Manifest 참조: 추가 메타데이터
    public let version: Int?
    public let playlistType: PlaylistType?
    public let discontinuitySequence: Int
    
    public var totalDuration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }
    
    /// The last segment's end time
    public var endTime: Double {
        guard let last = segments.last else { return 0 }
        return last.startTime + last.duration
    }

    /// VOD/EVENT/LIVE 판별
    public enum PlaylistType: String, Sendable {
        case vod = "VOD"
        case event = "EVENT"
    }

    /// AES-128 암호화 정보 (flashls Manifest 참조)
    public struct EncryptionInfo: Sendable, Equatable {
        public let method: EncryptionMethod
        public let uri: URL
        public let iv: Data?

        public enum EncryptionMethod: String, Sendable {
            case aes128 = "AES-128"
            case sampleAES = "SAMPLE-AES"
        }
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
        public let encryptionInfo: EncryptionInfo?
        public let discontinuitySequence: Int
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
    
    /// ISO8601DateFormatter는 내부에 ICU/NSCalendar 초기화가 포함되어 비용이 큼
    /// 매 PDT 라인마다 재생성하지 않고 static으로 한 번만 생성
    private nonisolated(unsafe) static let iso8601FracFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()
    private nonisolated(unsafe) static let iso8601PlainFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()
    
    public init() {}
    
    // MARK: - Master Playlist
    
    /// Parse a master playlist from M3U8 content
    public func parseMasterPlaylist(content: String, baseURL: URL) throws -> MasterPlaylist {
        // split은 Substring을 반환하여 원본 String storage 공유 (heap 할당 없음)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        
        guard lines.first?.hasPrefix("#EXTM3U") == true else {
            throw AppError.player(.invalidManifest)
        }
        
        var variants: [MasterPlaylist.Variant] = []
        var currentAttributes: [String: String] = [:]
        
        for line in lines {
            // Substring에서도 직접 작동 (StringProtocol)
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
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        
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

        // flashls Manifest 참조: 추가 메타데이터
        var version: Int?
        var playlistType: MediaPlaylist.PlaylistType?
        var discontinuitySequence: Int = 0
        var currentEncryption: MediaPlaylist.EncryptionInfo?
        var continuityIndex: Int = 0
        
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

            } else if trimmed.hasPrefix("#EXT-X-VERSION:") {
                version = Int(trimmed.dropFirst("#EXT-X-VERSION:".count))

            } else if trimmed.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                let typeStr = String(trimmed.dropFirst("#EXT-X-PLAYLIST-TYPE:".count))
                    .trimmingCharacters(in: .whitespaces)
                playlistType = MediaPlaylist.PlaylistType(rawValue: typeStr)

            } else if trimmed.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
                discontinuitySequence = Int(trimmed.dropFirst("#EXT-X-DISCONTINUITY-SEQUENCE:".count)) ?? 0
                continuityIndex = discontinuitySequence
                
            } else if trimmed.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                mediaSequence = Int(trimmed.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
                segmentIndex = mediaSequence

            } else if trimmed.hasPrefix("#EXT-X-KEY:") {
                // flashls Manifest.as 참조: AES-128 암호화 키 파싱
                let attrs = parseAttributes(String(trimmed.dropFirst("#EXT-X-KEY:".count)))
                let method = attrs["METHOD"] ?? "NONE"
                if method == "NONE" {
                    currentEncryption = nil
                } else if let encMethod = MediaPlaylist.EncryptionInfo.EncryptionMethod(rawValue: method),
                          let uriStr = attrs["URI"] {
                    let keyURL = resolveURL(uriStr, base: baseURL)
                    // flashls: IV 미제공 시 시퀀스 번호를 big-endian 16바이트로 변환하여 IV로 사용
                    let iv: Data? = attrs["IV"].flatMap { parseHexIV($0) }
                    currentEncryption = MediaPlaylist.EncryptionInfo(
                        method: encMethod,
                        uri: keyURL,
                        iv: iv
                    )
                }
                
            } else if trimmed.hasPrefix("#EXTINF:") {
                let durationStr = String(trimmed.dropFirst("#EXTINF:".count))
                    .components(separatedBy: ",").first ?? "0"
                currentDuration = Double(durationStr) ?? 0
                
            } else if trimmed.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                let dateStr = String(trimmed.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count))
                // static 캐시된 포매터 사용 — 세그먼트당 2개 DateFormatter 할당 제거
                currentPDT = Self.iso8601FracFormatter.date(from: dateStr)
                    ?? Self.iso8601PlainFormatter.date(from: dateStr)
                
            } else if trimmed == "#EXT-X-DISCONTINUITY" {
                currentDiscontinuity = true
                continuityIndex += 1
                
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
                // flashls: IV 미제공 시 시퀀스 번호를 big-endian 16바이트 IV로 사용
                let effectiveEncryption: MediaPlaylist.EncryptionInfo?
                if let enc = currentEncryption, enc.iv == nil {
                    effectiveEncryption = MediaPlaylist.EncryptionInfo(
                        method: enc.method,
                        uri: enc.uri,
                        iv: sequenceNumberToIV(segmentIndex)
                    )
                } else {
                    effectiveEncryption = currentEncryption
                }

                let segment = MediaPlaylist.Segment(
                    id: segmentIndex,
                    duration: currentDuration,
                    uri: resolveURL(trimmed, base: baseURL),
                    startTime: currentTime,
                    programDateTime: currentPDT,
                    discontinuity: currentDiscontinuity,
                    byteRange: currentByteRange,
                    parts: currentParts,
                    encryptionInfo: effectiveEncryption,
                    discontinuitySequence: continuityIndex
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
            isLowLatency: isLowLatency,
            version: version,
            playlistType: playlistType,
            discontinuitySequence: discontinuitySequence
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

    // MARK: - AES-128 Helpers (flashls Manifest.as 참조)

    /// "0x..." 형식의 16진수 IV 문자열을 16바이트 Data로 변환
    private func parseHexIV(_ hex: String) -> Data? {
        var hexStr = hex.trimmingCharacters(in: .whitespaces)
        if hexStr.hasPrefix("0x") || hexStr.hasPrefix("0X") {
            hexStr = String(hexStr.dropFirst(2))
        }
        // 32자 미만이면 앞에 0을 패딩하여 16바이트(32 hex chars)로 맞춤
        while hexStr.count < 32 { hexStr = "0" + hexStr }
        guard hexStr.count == 32 else { return nil }

        var data = Data(capacity: 16)
        var index = hexStr.startIndex
        for _ in 0..<16 {
            let nextIndex = hexStr.index(index, offsetBy: 2)
            guard let byte = UInt8(hexStr[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    /// flashls: IV 미제공 시 시퀀스 번호를 big-endian 16바이트로 변환하여 IV로 사용
    private func sequenceNumberToIV(_ seqNum: Int) -> Data {
        var data = Data(repeating: 0, count: 16)
        var value = UInt64(seqNum)
        // big-endian: 하위 8바이트에 시퀀스 번호 저장
        for i in stride(from: 15, through: 8, by: -1) {
            data[i] = UInt8(value & 0xFF)
            value >>= 8
        }
        return data
    }
}
