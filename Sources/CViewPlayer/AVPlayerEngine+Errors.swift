// MARK: - AVPlayerEngine+Errors.swift
// CViewPlayer - AVPlayer / URLSession 오류 → PlayerError 분류기
//
// 설계 목표
//   - 에러 분류 로직을 순수 함수로 분리 → 단위 테스트 용이
//   - AVFoundationErrorDomain + NSURLErrorDomain 양쪽 매핑
//   - 기본값은 보수적으로 .engineInitFailed 또는 .networkTimeout

import Foundation
import AVFoundation
import CViewCore

// MARK: - Error Classifier

internal enum AVPlayerErrorClassifier {

    /// NSError → PlayerError 매핑. 알 수 없는 에러는 `.engineInitFailed`로 정규화.
    static func classify(_ error: Error) -> PlayerError {
        let nsError = error as NSError

        // AVFoundation 도메인
        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case AVError.contentIsNotAuthorized.rawValue:
                return .streamNotFound
            case AVError.noLongerPlayable.rawValue:
                return .connectionLost
            case AVError.serverIncorrectlyConfigured.rawValue:
                return .networkTimeout
            case AVError.decodeFailed.rawValue,
                 AVError.failedToLoadMediaData.rawValue:
                return .decodingFailed(nsError.localizedDescription)
            case AVError.fileFormatNotRecognized.rawValue,
                 AVError.contentIsUnavailable.rawValue:
                return .unsupportedFormat(nsError.localizedDescription)
            default:
                break
            }
        }

        // URL 로딩 도메인
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost:
                return .connectionLost
            case NSURLErrorTimedOut:
                return .networkTimeout
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
                return .invalidManifest
            case NSURLErrorUserAuthenticationRequired,
                 NSURLErrorUserCancelledAuthentication:
                return .authRequired
            default:
                return .networkTimeout
            }
        }

        return .engineInitFailed
    }

    /// 에러가 재연결로 복구 가능한 유형인지 판단.
    static func isRecoverable(_ error: PlayerError) -> Bool {
        switch error {
        case .connectionLost, .networkTimeout:
            return true
        default:
            return false
        }
    }
}

// MARK: - Live Stream URL Detector

internal enum AVPlayerStreamDetector {
    static func isLive(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let str = url.absoluteString.lowercased()
        if ext == "m3u8" || ext == "m3u" { return true }
        if str.contains(".m3u8") || str.contains("/live") || str.contains("hls") { return true }
        return false
    }
}
