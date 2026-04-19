// MARK: - CViewCore/Models/StreamProxyMode.swift
// 스트림 프록시 / 인터셉트 모드 — 사용자가 설정에서 선택
//
// chzzk CDN 이 fMP4 세그먼트를 잘못된 Content-Type(`video/MP2T`) 으로 응답하는
// 이슈를 해결하기 위한 다양한 전략을 옵션으로 노출한다.

import Foundation

public enum StreamProxyMode: String, Codable, Sendable, CaseIterable {
    /// 기본값. 로컬 HTTP 프록시(`LocalStreamProxy`, NWListener) 경유.
    /// VLC/AVPlayer/HLS.js 모두 안정적으로 작동.
    case localProxy = "localProxy"

    /// AVPlayer 인-프로세스 인터셉터. `AVAssetResourceLoaderDelegate` + 커스텀 스킴.
    /// 별도 포트 점유 없음. macOS HLS LIVE 와 조합 시 일부 환경에서 -12881 발생 가능 (실험적).
    /// VLC 엔진에는 효과 없음 → VLC 사용 시 자동으로 localProxy 로 폴백.
    case avInterceptor = "avInterceptor"

    /// 글로벌 `URLProtocol` 등록. CFNetwork 기반 요청에만 적용.
    /// 매니페스트 fetch / 썸네일 등에는 효과적이나, AVPlayer/VLC 의 내부 미디어
    /// 네트워크는 후크되지 않으므로 단독으로는 재생 보정 불가 (실험적, 진단용).
    case urlProtocolHook = "urlProtocolHook"

    /// VLC `:demux=adaptive,hls` 강제. Content-Type 무시하고 데모서를 직접 지정.
    /// AVPlayer 엔진에는 효과 없음 → AVPlayer 사용 시 자동으로 localProxy 로 폴백.
    case directVLCAdaptive = "directVLCAdaptive"

    /// AVPlayer `AVAssetDownloadURLSession` 활용 시도. 다운로드 세션은 일반적으로
    /// VOD/오프라인 용도이지만, Content-Type 부분 우회 가능성 탐색용 (실험적).
    case avAssetDownload = "avAssetDownload"

    /// 직접 재생. 어떤 보정도 하지 않음. 디버깅용.
    case none = "none"

    public var displayName: String {
        switch self {
        case .localProxy:        "로컬 프록시 (기본)"
        case .avInterceptor:     "AV 인-프로세스 인터셉터"
        case .urlProtocolHook:   "URLProtocol 글로벌 후크"
        case .directVLCAdaptive: "VLC 직접 (adaptive demux)"
        case .avAssetDownload:   "AVAsset 다운로드 세션"
        case .none:              "직접 재생 (보정 없음)"
        }
    }

    public var description: String {
        switch self {
        case .localProxy:
            "로컬 HTTP 프록시(127.0.0.1) 경유로 Content-Type 을 교정합니다. 가장 안정적입니다."
        case .avInterceptor:
            "AVPlayer 전용. 별도 포트 없이 인-프로세스에서 응답을 가로챕니다. 일부 macOS 환경에서 재생 실패 가능."
        case .urlProtocolHook:
            "URLProtocol 을 글로벌 등록. 매니페스트/썸네일 등 보조 요청만 후크되며 미디어 재생에는 영향이 적습니다."
        case .directVLCAdaptive:
            "VLC 전용. 데모서를 강제로 adaptive(HLS)로 지정해 잘못된 Content-Type 을 무시합니다."
        case .avAssetDownload:
            "AVPlayer 전용. AVAssetDownloadURLSession 으로 자산을 로드합니다. 라이브에서는 작동이 보장되지 않는 실험 옵션."
        case .none:
            "어떤 보정도 하지 않고 원본 URL 을 그대로 사용합니다. 디버깅/네트워크 비교용."
        }
    }

    public var isExperimental: Bool {
        switch self {
        case .localProxy, .none: false
        case .avInterceptor, .urlProtocolHook, .directVLCAdaptive, .avAssetDownload: true
        }
    }
}
