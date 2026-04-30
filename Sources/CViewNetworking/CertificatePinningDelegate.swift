// MARK: - CViewNetworking/CertificatePinningDelegate.swift
// 치지직 API 도메인 SSL 인증서 핀닝 — SPKI SHA256 기반

import Foundation
import Security
import CryptoKit
import os.log
import CViewCore

// MARK: - Configuration

/// 인증서 핀닝 설정
public struct CertificatePinningConfiguration: Sendable {
    /// 핀닝 위반 시 연결을 차단할지 여부 (false = report-only 모드)
    public let enforcePinning: Bool
    /// 핀닝 대상 도메인 → 허용된 SPKI SHA256 해시 매핑
    public let pinnedDomains: [String: Set<String>]

    public init(
        enforcePinning: Bool = false,
        pinnedDomains: [String: Set<String>] = CertificatePinningDefaults.pinnedDomains
    ) {
        self.enforcePinning = enforcePinning
        self.pinnedDomains = pinnedDomains
    }
}

// MARK: - Defaults

/// 치지직 API 도메인 SPKI SHA256 해시 기본값
///
/// 핀은 서버 인증서와 중간 CA 인증서의 SubjectPublicKeyInfo(SPKI) SHA256 해시입니다.
/// 인증서 갱신 시 공개키가 유지되면 핀은 변경되지 않습니다.
/// CA 핀을 포함하여 인증서 회전 시에도 안전하게 동작합니다.
///
/// 핀 추출 방법:
/// ```
/// openssl s_client -connect api.chzzk.naver.com:443 -servername api.chzzk.naver.com < /dev/null 2>/dev/null \
///   | openssl x509 -pubkey -noout \
///   | openssl pkey -pubin -outform DER \
///   | openssl dgst -sha256 -binary \
///   | base64
/// ```
public enum CertificatePinningDefaults: Sendable {
    /// 핀닝 대상 치지직 API 도메인 목록
    public static let pinnedDomainNames: Set<String> = [
        "api.chzzk.naver.com",
        "chzzk.naver.com",
        "comm-api.game.naver.com",
        "apis.naver.com",
    ]

    /// 도메인별 허용된 SPKI SHA256 해시 (Base64 인코딩)
    ///
    /// 현재는 빈 상태 — report-only 모드에서 런타임 로그로 실제 핀을 수집한 뒤,
    /// 검증된 값을 여기에 추가할 수 있습니다.
    /// 핀이 비어 있으면 핀닝을 건너뛰고 모든 유효한 인증서를 허용합니다.
    ///
    /// 예시 (실제 값으로 교체 필요):
    /// ```
    /// "api.chzzk.naver.com": [
    ///     "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",  // leaf cert
    ///     "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",  // intermediate CA
    /// ]
    /// ```
    public static let pinnedDomains: [String: Set<String>] = {
        var domains: [String: Set<String>] = [:]
        for domain in pinnedDomainNames {
            domains[domain] = []  // 빈 핀 세트 = report-only에서 로그만 수집
        }
        return domains
    }()
}

// MARK: - Delegate

/// URLSession SSL 인증서 핀닝 델리게이트
///
/// `urlSession(_:didReceive:completionHandler:)` 에서 서버 인증서 체인의
/// 공개키 SPKI SHA256 해시를 검증합니다.
///
/// - Report-only 모드 (기본): 핀 불일치 시 경고 로그만 남기고 연결 허용
/// - Enforce 모드: 핀 불일치 시 연결 차단 (`.cancelAuthenticationChallenge`)
///
/// **Sendable**: 모든 상태가 불변이므로 안전합니다.
public final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {
    private let configuration: CertificatePinningConfiguration
    private static let logger = Logger(subsystem: "com.cview.app", category: "CertPinning")

    /// ASN.1 DER prefix for RSA 2048-bit SPKI (RFC 3279)
    /// This prefix is prepended to the raw public key data before hashing
    /// to produce the SubjectPublicKeyInfo hash.
    private static let rsaAsn1HeaderPrefix: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09,
        0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
        0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00,
    ]

    /// ASN.1 DER prefix for EC P-256 SPKI
    private static let ecDsaSecp256r1Asn1HeaderPrefix: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86,
        0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
        0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00,
    ]

    /// ASN.1 DER prefix for EC P-384 SPKI
    private static let ecDsaSecp384r1Asn1HeaderPrefix: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2A, 0x86,
        0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05, 0x2B,
        0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00,
    ]

    public init(configuration: CertificatePinningConfiguration = CertificatePinningConfiguration()) {
        self.configuration = configuration
        super.init()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // 핀닝 대상 도메인이 아니면 기본 처리
        guard let expectedPins = configuration.pinnedDomains[host] else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 핀이 비어 있으면 핀닝을 건너뛰고 로그만 수집
        if expectedPins.isEmpty {
            logCertificateChain(serverTrust: serverTrust, host: host, context: "discovery")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 표준 신뢰 평가 수행
        var secError: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &secError)

        guard isTrusted else {
            Self.logger.error("SSL trust evaluation failed for \(host, privacy: .public): \(String(describing: secError), privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 인증서 체인의 모든 공개키 SPKI 해시와 비교
        let chainCount = SecTrustGetCertificateCount(serverTrust)
        var matched = false

        for index in 0..<chainCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }

            if let spkiHash = spkiSHA256Hash(for: certificate) {
                if expectedPins.contains(spkiHash) {
                    matched = true
                    Self.logger.debug("Pin matched at chain index \(index) for \(host, privacy: .public)")
                    break
                }
            }
        }

        if matched {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // 핀 불일치
            logCertificateChain(serverTrust: serverTrust, host: host, context: "mismatch")

            if configuration.enforcePinning {
                Self.logger.error("Certificate pinning ENFORCED — blocking connection to \(host, privacy: .public)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            } else {
                Self.logger.warning("Certificate pinning violation (report-only) for \(host, privacy: .public) — allowing connection")
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            }
        }
    }

    // MARK: - SPKI Hash Computation

    /// 인증서에서 SubjectPublicKeyInfo (SPKI) SHA256 해시를 Base64로 계산
    private func spkiSHA256Hash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            Self.logger.warning("Failed to extract public key from certificate")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            Self.logger.warning("Failed to get external representation of public key: \(String(describing: error?.takeRetainedValue()), privacy: .public)")
            return nil
        }

        // ASN.1 헤더 선택 (키 타입에 따라)
        let header: [UInt8]
        let keyType = SecKeyCopyAttributes(publicKey) as? [String: Any]
        let type = keyType?[kSecAttrKeyType as String] as? String
        let size = keyType?[kSecAttrKeySizeInBits as String] as? Int

        if type == (kSecAttrKeyTypeRSA as String) {
            header = Self.rsaAsn1HeaderPrefix
        } else if type == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            if size == 384 {
                header = Self.ecDsaSecp384r1Asn1HeaderPrefix
            } else {
                header = Self.ecDsaSecp256r1Asn1HeaderPrefix
            }
        } else {
            // 알 수 없는 키 타입 — 헤더 없이 해시 (best effort)
            Self.logger.info("Unknown key type: \(type ?? "nil", privacy: .public), size: \(size ?? 0)")
            header = []
        }

        // SPKI = ASN.1 header + raw public key
        var spkiData = Data(header)
        spkiData.append(publicKeyData)

        // SHA256 해시 후 Base64 인코딩
        let hash = SHA256.hash(data: spkiData)
        return Data(hash).base64EncodedString()
    }

    // MARK: - Logging

    /// 인증서 체인의 SPKI 해시를 로그로 기록 (핀 수집 및 디버깅용)
    private func logCertificateChain(serverTrust: SecTrust, host: String, context: String) {
        let chainCount = SecTrustGetCertificateCount(serverTrust)
        Self.logger.info("Certificate chain for \(host, privacy: .public) (\(context, privacy: .public), \(chainCount) certs):")

        for index in 0..<chainCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }

            let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
            let spkiHash = spkiSHA256Hash(for: certificate) ?? "N/A"

            Self.logger.info("  [\(index)] Subject: \(subject, privacy: .public)")
            Self.logger.info("  [\(index)] SPKI SHA256: \(spkiHash, privacy: .public)")
        }
    }
}
