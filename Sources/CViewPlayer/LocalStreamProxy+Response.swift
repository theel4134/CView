// MARK: - LocalStreamProxy+Response.swift
// CViewPlayer - HTTP Response Helpers + M3U8 URL Rewriting

import Foundation
import Network

extension LocalStreamProxy {
    
    // MARK: - HTTP Response Helpers (Keep-Alive)
    
    func sendResponse(to connection: NWConnection, status: Int, contentType: String, data: Data, requestNum: Int, keepAlive: Bool = true) {
        var header = "HTTP/1.1 \(status) OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(data.count)\r\n"
        if keepAlive {
            header += "Connection: keep-alive\r\n"
            header += "Keep-Alive: timeout=\(Int(keepAliveTimeout))\r\n"
        } else {
            header += "Connection: close\r\n"
        }
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "\r\n"
        
        var fullResponse = Data(header.utf8)
        fullResponse.append(data)
        
        connection.send(content: fullResponse, contentContext: .defaultMessage, isComplete: !keepAlive, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.debug("Proxy response send: \(error.localizedDescription, privacy: .public)")
                connection.cancel()
                return
            }
            if keepAlive {
                self?.readHTTPRequest(from: connection, requestCount: requestNum)
            } else {
                connection.cancel()
            }
        })
    }
    
    func sendError(to connection: NWConnection, status: Int, message: String, keepAlive: Bool) {
        let body = message.data(using: .utf8) ?? Data()
        var header = "HTTP/1.1 \(status) \(message)\r\n"
        header += "Content-Type: text/plain\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        header += "\r\n"
        
        var fullResponse = Data(header.utf8)
        fullResponse.append(body)
        
        connection.send(content: fullResponse, contentContext: .defaultMessage, isComplete: !keepAlive, completion: .contentProcessed { [weak self] _ in
            if keepAlive {
                self?.readHTTPRequest(from: connection, requestCount: 0)
            } else {
                connection.cancel()
            }
        })
    }
    
    // MARK: - Single-Pass M3U8 URL Rewriting
    
    /// 단일 정규식 스캔으로 sameHost + crossCDN URL을 동시 치환
    /// 기존: replacingOccurrences×(1+N) + regex 1회 = O(M×(1+N))
    /// 개선: regex 1회 + 역순 치환 = O(M) (M=M3U8 길이)
    func rewriteM3U8URLs(_ content: String, proxyBase: String) -> String {
        // https:// 뒤에 CDN 호스트가 오는 패턴 + 현재 타겟 호스트 모두 매치
        // cdnRegex는 navercdn.com|pstatic.net|naver.com|akamaized.net 호스트를 매치
        // 타겟 호스트도 포함되므로 단일 패스로 처리
        let regex = LocalStreamProxy.cdnRegex
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        
        // 모든 매치를 수집 (range가 큰 쪽부터 치환하기 위해)
        let matches = regex.matches(in: content, range: fullRange)
        guard !matches.isEmpty else { return content }
        
        var result = content
        // 역순으로 치환하여 앞쪽 인덱스가 무효화되지 않도록
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let hostRange = Range(match.range(at: 1), in: result) else { continue }
            let host = String(result[hostRange])
            
            let replacement: String
            if host == targetHost {
                // 동일 호스트 → 프록시 주소로 직접 치환
                replacement = proxyBase
            } else {
                // 크로스CDN → /_p_/HOST 인코딩
                replacement = "\(proxyBase)/_p_/\(host)"
            }
            result.replaceSubrange(fullRange, with: replacement)
        }
        
        return result
    }
    
    // MARK: - M3U8 URL Absolutization
    
    /// CDN URL에서 디렉토리 경로 추출 (percent-encoding 보존)
    /// "https://host/path/to/file.m3u8?q=v" → "/path/to/"
    func extractDirectoryPath(from urlString: String) -> String {
        guard let protEnd = urlString.range(of: "://") else { return "/" }
        let rest = urlString[protEnd.upperBound...]
        guard let pathStart = rest.firstIndex(of: "/") else { return "/" }
        var path = String(rest[pathStart...])
        // 쿼리 스트링 제거
        if let qIdx = path.firstIndex(of: "?") {
            path = String(path[..<qIdx])
        }
        // 마지막 '/' 까지가 디렉토리 (% 인코딩된 %2f는 무시 — 실제 '/'만 기준)
        if let lastSlash = path.lastIndex(of: "/") {
            return String(path[...lastSlash])
        }
        return "/"
    }
    
    /// M3U8 내 모든 상대 URL을 절대 프록시 URL로 변환
    /// master playlist의 variant URL + chunklist의 segment URL 모두 처리
    /// VLC가 %2f 포함 경로에서 상대 URL 해석 실패 → 절대 URL로 우회
    func makeRelativeURLsAbsolute(_ content: String, proxyBase: String, basePath: String) -> String {
        content.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let lineStr = String(line)
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // #EXT-X-MAP:URI="..." → 절대 URL로 변환
            if trimmed.hasPrefix("#EXT-X-MAP:") {
                if let uriStart = lineStr.range(of: "URI=\""),
                   let closingQuote = lineStr[uriStart.upperBound...].firstIndex(of: "\"") {
                    let uri = String(lineStr[uriStart.upperBound..<closingQuote])
                    if !uri.hasPrefix("http") {
                        let absolute = "\(proxyBase)\(basePath)\(uri)"
                        return lineStr.replacingCharacters(in: uriStart.upperBound..<closingQuote, with: absolute)
                    }
                }
                return lineStr
            }
            
            // 빈 줄, 주석 줄 → 그대로 통과
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                return lineStr
            }
            
            // 비-# 줄 = URI (variant 또는 segment) → 상대이면 절대로 변환
            if !trimmed.hasPrefix("http") {
                return "\(proxyBase)\(basePath)\(trimmed)"
            }
            
            return lineStr
        }.joined(separator: "\n")
    }
}
