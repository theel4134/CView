// MARK: - ChatTTSService.swift
// CViewApp - 후원/구독 메시지 음성 읽기(TTS) 서비스

import Foundation
import AVFoundation
import CViewCore

/// 후원/구독 메시지를 음성으로 읽어주는 TTS 서비스
/// AVSpeechSynthesizer 기반, 큐 방식 (최대 5개 대기)
@MainActor
final class ChatTTSService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [String] = []
    private let maxQueueSize = 5
    private var isSpeaking = false

    var isEnabled: Bool = false
    var volume: Float = 0.8
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var voiceIdentifier: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 후원/구독 메시지를 TTS 큐에 추가
    func enqueue(_ message: ChatMessageItem) {
        guard isEnabled else { return }
        guard let text = formatTTSText(message) else { return }
        guard queue.count < maxQueueSize else { return }
        queue.append(text)
        speakNextIfIdle()
    }

    /// TTS 중지 및 큐 초기화
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.removeAll()
        isSpeaking = false
    }

    // MARK: - Private

    private func formatTTSText(_ message: ChatMessageItem) -> String? {
        if message.type == .donation, let amount = message.donationAmount {
            let content = message.content.isEmpty ? "" : ". \(message.content)"
            return "\(message.nickname)님이 \(amount)원 후원\(content)"
        } else if message.type == .subscription {
            if let months = message.subscriptionMonths, months > 0 {
                return "\(message.nickname)님이 \(months)개월 구독"
            }
            return "\(message.nickname)님이 구독"
        }
        return nil
    }

    private func speakNextIfIdle() {
        guard !isSpeaking, !queue.isEmpty else { return }
        let text = queue.removeFirst()
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = volume
        utterance.rate = rate
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.speakNextIfIdle()
        }
    }
}
