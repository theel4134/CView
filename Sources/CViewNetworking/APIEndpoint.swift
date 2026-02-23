// MARK: - CViewNetworking/APIEndpoint.swift
// 치지직 API 엔드포인트 정의 — Type-safe

import Foundation
import CViewCore

/// 치지직 API 엔드포인트
public enum ChzzkEndpoint: EndpointProtocol, Sendable {
    // MARK: - Channel
    case channelInfo(channelId: String)
    case liveDetail(channelId: String)
    case liveStatus(channelId: String)

    // MARK: - Following
    case following(size: Int, page: Int)
    case follow(channelId: String)
    case unfollow(channelId: String)

    // MARK: - Search
    case searchChannel(keyword: String, offset: Int, size: Int)
    case searchLive(keyword: String, offset: Int, size: Int)
    case searchVideo(keyword: String, offset: Int, size: Int)

    // MARK: - Chat
    case chatAccessToken(chatChannelId: String)

    // MARK: - VOD
    case vodList(channelId: String, page: Int, size: Int)
    case vodDetail(videoNo: Int)

    // MARK: - Clip
    case clipList(channelId: String, page: Int, size: Int)
    case clipDetail(clipUID: String)
    case clipInkey(clipUID: String)
    case homePopularClips(filterType: String, orderType: String)

    // MARK: - Top/Trending
    case topLives(size: Int, concurrentUserCount: Int? = nil, liveId: Int? = nil)

    // MARK: - User
    case userStatus

    // MARK: - Emoticon
    case emoticonDeploy(channelId: String)
    case emoticonPack(packId: String)
    case userEmoticons         // 사용자가 쓸 수 있는 전체 이모티콘 팩 (인증 필요)
    case basicEmoticonPacks    // 치지직 기본 이모티콘 팩 목록 (인증 불필요)

    // MARK: - EndpointProtocol

    public var path: String {
        switch self {
        case .channelInfo(let id):
            "/service/v1/channels/\(id)"
        case .liveDetail(let id):
            "/service/v3/channels/\(id)/live-detail"
        case .liveStatus(let id):
            "/polling/v1/channels/\(id)/live-status"
        case .following:
            "/service/v1/channels/followings"
        case .follow(let id), .unfollow(let id):
            "/service/v1/channels/\(id)/follow"
        case .searchChannel:
            "/service/v1/search/channels"
        case .searchLive:
            "/service/v1/search/lives"
        case .searchVideo:
            "/service/v1/search/videos"
        case .chatAccessToken(let id):
            "/polling/v3/channels/\(id)/access-token"
        case .vodList(let id, _, _):
            "/service/v3/channels/\(id)/videos"
        case .vodDetail(let videoNo):
            "/service/v3/videos/\(videoNo)"
        case .clipList(let id, _, _):
            "/service/v1/channels/\(id)/clips"
        case .clipDetail(let uid):
            "/service/v1/clips/\(uid)/detail"
        case .clipInkey(let uid):
            "/service/v1/clips/\(uid)/inkey"
        case .homePopularClips:
            "/service/v1/home/recommended/clips"
        case .topLives:
            "/service/v1/lives"
        case .userStatus:
            "/service/v1/users/me"
        case .emoticonDeploy(let id):
            "/service/v1/channels/\(id)/emoticon-deploy"
        case .emoticonPack(let packId):
            "/service/v1/emoticon-packs/\(packId)"
        case .userEmoticons:
            "/service/v2/emoticons"
        case .basicEmoticonPacks:
            "/service/v1/emoticons"
        }
    }

    public var method: HTTPMethod {
        switch self {
        case .follow: .post
        case .unfollow: .delete
        case .clipInkey: .post
        default: .get
        }
    }
    public var body: Data? {
        switch self {
        case .clipInkey:
            return "{}".data(using: .utf8)
        default:
            return nil
        }
    }

    public var queryItems: [URLQueryItem]? {
        switch self {
        case .following(let size, let page):
            var items = [
                URLQueryItem(name: "size", value: "\(size)"),
                URLQueryItem(name: "sortType", value: "FOLLOW")
            ]
            if page > 0 {
                items.append(URLQueryItem(name: "page", value: "\(page)"))
            }
            return items
        case .searchChannel(let keyword, let offset, let size),
             .searchLive(let keyword, let offset, let size),
             .searchVideo(let keyword, let offset, let size):
            return [URLQueryItem(name: "keyword", value: keyword),
             URLQueryItem(name: "offset", value: "\(offset)"),
             URLQueryItem(name: "size", value: "\(size)")]
        case .vodList(_, let page, let size):
            return [URLQueryItem(name: "page", value: "\(page)"),
             URLQueryItem(name: "size", value: "\(size)"),
             URLQueryItem(name: "sortType", value: "LATEST")]
        case .clipList(_, let page, let size):
            return [URLQueryItem(name: "page", value: "\(page)"),
             URLQueryItem(name: "size", value: "\(size)")]
        case .clipDetail:
            return [
                URLQueryItem(name: "optionalProperties", value: "COMMENT"),
                URLQueryItem(name: "optionalProperties", value: "PRIVATE_USER_BLOCK"),
                URLQueryItem(name: "optionalProperties", value: "PENALTY"),
                URLQueryItem(name: "optionalProperties", value: "MAKER_CHANNEL"),
                URLQueryItem(name: "optionalProperties", value: "OWNER_CHANNEL")
            ]
        case .homePopularClips(let filterType, let orderType):
            return [
                URLQueryItem(name: "filterType", value: filterType),
                URLQueryItem(name: "orderType", value: orderType),
                URLQueryItem(name: "optionalProperties", value: "OWNER_CHANNEL"),
                URLQueryItem(name: "optionalProperties", value: "MAKER_CHANNEL")
            ]
        case .topLives(let size, let concurrentUserCount, let liveId):
            var items = [URLQueryItem(name: "size", value: "\(size)")]
            if let c = concurrentUserCount { items.append(URLQueryItem(name: "concurrentUserCount", value: "\(c)")) }
            if let l = liveId { items.append(URLQueryItem(name: "liveId", value: "\(l)")) }
            return items
        default:
            return nil
        }
    }

    public var requiresAuth: Bool {
        switch self {
        case .following, .userStatus, .follow, .unfollow: true
        case .clipInkey: true
        case .userEmoticons: true   // 개인화 이모티콘은 로그인 필요
        // emoticonDeploy: 공개 이모티콘은 인증 불필요. 쿠키 있으면 자동으로 구독 팩도 포함됨 (softAuth)
        case .chatAccessToken: false  // 인증 없이도 READ 토큰 발급 가능 (인증 시 SEND 권한)
        default: false
        }
    }

    public var cachePolicy: CachePolicy {
        switch self {
        case .liveStatus, .chatAccessToken:
            .reloadIgnoringCache
        case .channelInfo:
            .returnCacheElseLoad(ttl: 300)
        default:
            .returnCacheElseLoad(ttl: 60)
        }
    }
}
