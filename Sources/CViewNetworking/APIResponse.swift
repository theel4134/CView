// MARK: - CViewNetworking/APIResponse.swift
// 치지직 API 응답 래퍼

import Foundation
import os

/// 치지직 API 표준 응답 래퍼
public struct ChzzkResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let message: String?
    public let content: T?

    public init(code: Int, message: String? = nil, content: T? = nil) {
        self.code = code
        self.message = message
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, content
    }

    /// 방어적 디코딩: code/message/content 누락 시에도 최대한 복원
    public init(from decoder: Decoder) throws {
        let logger = os.Logger(subsystem: "com.cview.app", category: "ChzzkResponse")
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // code: 없으면 -1 (알 수 없음)
        if let codeValue = try? container.decode(Int.self, forKey: .code) {
            self.code = codeValue
        } else {
            logger.warning("ChzzkResponse: 'code' 필드 누락, 기본값 -1 사용")
            self.code = -1
        }

        // message: 없으면 nil
        self.message = try? container.decode(String.self, forKey: .message)

        // content: 없거나 디코딩 실패 시 nil + 경고
        if container.contains(.content) {
            do {
                self.content = try container.decodeIfPresent(T.self, forKey: .content)
            } catch {
                logger.warning("ChzzkResponse: 'content' 디코딩 실패 (\(error.localizedDescription, privacy: .public)), nil 처리")
                self.content = nil
            }
        } else {
            logger.warning("ChzzkResponse: 'content' 필드 누락")
            self.content = nil
        }
    }
}

/// 페이지네이션 응답
public struct PagedContent<T: Decodable & Sendable>: Decodable, Sendable {
    public let size: Int
    public let totalCount: Int?
    public let data: [T]
    /// 라이브 목록 커서 기반 다음 페이지 정보
    public let page: LivePageInfo?

    public init(size: Int = 0, totalCount: Int? = nil, data: [T] = [], page: LivePageInfo? = nil) {
        self.size = size
        self.totalCount = totalCount
        self.data = data
        self.page = page
    }

    private enum CodingKeys: String, CodingKey {
        case size, totalCount, data, page
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = (try? container.decode(Int.self, forKey: .size)) ?? 0
        totalCount = try? container.decode(Int.self, forKey: .totalCount)
        data = (try? container.decode([T].self, forKey: .data)) ?? []
        page = try? container.decode(LivePageInfo.self, forKey: .page)
    }
}

/// 전체 라이브 수집 진행률
public struct AllLivesProgress: Sendable {
    public let currentCount: Int
    public let estimatedTotal: Int?
    public let currentPage: Int
    public let deduplicatedCount: Int
}

/// 라이브 목록 커서 페이지네이션 정보
public struct LivePageInfo: Decodable, Sendable {
    public let next: LivePageCursor?
    public let prev: LivePageCursor?
}

/// 라이브 목록 커서 (concurrentUserCount + liveId)
public struct LivePageCursor: Decodable, Sendable {
    public let concurrentUserCount: Int?
    public let liveId: Int?
}

/// 팔로잉 API 응답
public struct FollowingContent: Decodable, Sendable {
    public let followingList: [FollowingItem]?
    public let totalCount: Int?
    public let size: Int?
    public let page: FollowingPage?

    private enum CodingKeys: String, CodingKey {
        case followingList, totalCount, size, page
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        followingList = try? container.decode([FollowingItem].self, forKey: .followingList)
        totalCount = try? container.decode(Int.self, forKey: .totalCount)
        size = try? container.decode(Int.self, forKey: .size)
        page = try? container.decode(FollowingPage.self, forKey: .page)
    }

    public init(followingList: [FollowingItem]? = nil, totalCount: Int? = nil, size: Int? = nil, page: FollowingPage? = nil) {
        self.followingList = followingList
        self.totalCount = totalCount
        self.size = size
        self.page = page
    }
}

/// 팔로잉 페이지네이션 정보
public struct FollowingPage: Decodable, Sendable {
    public let next: FollowingPageOffset?
    
    public struct FollowingPageOffset: Decodable, Sendable {
        public let offset: Int?
    }
}

/// 팔로잉 개별 항목
public struct FollowingItem: Decodable, Sendable {
    public let streamer: FollowingStreamer?
    public let channel: FollowingChannelData?

    public init(streamer: FollowingStreamer? = nil, channel: FollowingChannelData? = nil) {
        self.streamer = streamer
        self.channel = channel
    }
}

/// 팔로잉 스트리머 데이터
public struct FollowingStreamer: Decodable, Sendable {
    /// true = 방송 중, false = 방송 종료, nil = 응답에 키 없음 (방송 중으로 간주)
    public let openLive: Bool?
    /// 일부 치지직 API 버전에서 사용하는 대체 라이브 상태 필드
    public let liveStatus: String?

    public init(openLive: Bool? = nil, liveStatus: String? = nil) {
        self.openLive = openLive
        self.liveStatus = liveStatus
    }

    /// 라이브 여부 통합 판단:
    /// - openLive 가 명시적으로 false이면 오프라인
    /// - openLive 가 nil(키 누락)이거나 true이면 라이브
    /// - liveStatus == "OPEN" 이면 라이브
    public var isActuallyLive: Bool {
        if let status = liveStatus { return status == "OPEN" }
        return openLive ?? true   // nil = 치지직이 streamer 객체를 반환했으나 키를 생략 → 라이브로 간주
    }
}

/// 팔로잉 채널 데이터
public struct FollowingChannelData: Decodable, Sendable {
    public let channelId: String?
    public let channelName: String?
    public let channelImageUrl: String?
    public let verifiedMark: Bool?

    public init(
        channelId: String? = nil,
        channelName: String? = nil,
        channelImageUrl: String? = nil,
        verifiedMark: Bool? = nil
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.channelImageUrl = channelImageUrl
        self.verifiedMark = verifiedMark
    }
}

/// 사용자 상태 정보
public struct UserStatusInfo: Decodable, Sendable {
    public let hasProfile: Bool?
    public let userIdHash: String?
    public let nickname: String?
    public let profileImageURL: String?
    public let penalties: [String]?
    public let loggedIn: Bool?

    public init(
        hasProfile: Bool? = nil,
        userIdHash: String? = nil,
        nickname: String? = nil,
        profileImageURL: String? = nil,
        penalties: [String]? = nil,
        loggedIn: Bool? = nil
    ) {
        self.hasProfile = hasProfile
        self.userIdHash = userIdHash
        self.nickname = nickname
        self.profileImageURL = profileImageURL
        self.penalties = penalties
        self.loggedIn = loggedIn
    }

    private enum CodingKeys: String, CodingKey {
        case hasProfile, userIdHash, nickname
        case profileImageURL = "profileImageUrl"
        case penalties, loggedIn
    }
}

// MARK: - JSON Decoder Extension

/// 날짜 파서 — static 인스턴스로 재사용. JSONDecoder는 단일 스레드에서 실행되므로 안전.
private enum ChzzkDateParsers {
    nonisolated(unsafe) static let iso8601WithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let iso8601 = ISO8601DateFormatter()
    nonisolated(unsafe) static let legacy: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

extension JSONDecoder {
    /// 치지직 API용 JSON 디코더 — 동시 사용 안전을 위해 매번 새 인스턴스 반환
    public static var chzzk: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // ISO 8601 (소수초 포함 및 미포함 순서로 시도)
            if let date = ChzzkDateParsers.iso8601WithFrac.date(from: dateString) {
                return date
            }
            if let date = ChzzkDateParsers.iso8601.date(from: dateString) {
                return date
            }

            // yyyy-MM-dd HH:mm:ss
            if let date = ChzzkDateParsers.legacy.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }
}
