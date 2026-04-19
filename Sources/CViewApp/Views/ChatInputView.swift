// MARK: - ChatInputView.swift
// CViewApp - 채팅 입력 영역 (이모티콘 · 자동완성 · 전송)

import SwiftUI
import CViewCore
import CViewChat
import CViewUI

// MARK: - Chat Input View (Premium)

struct ChatInputView: View {
    let viewModel: ChatViewModel?
    /// 컴팩트 모드 — 그리드 셀/통합 모드의 좁은 공간에서 사용
    /// · 이모티콘 버튼 숨김
    /// · 폰트/패딩/버튼 크기 축소
    /// · placeholder 단축
    var compact: Bool = false
    /// 컴팩트 모드 시 placeholder에 표시할 채널명 (옵션)
    var compactChannelHint: String? = nil
    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var showEmoticonPicker = false
    @State private var isEmoticonHovered = false
    @State private var isSendHovered = false

    /// 채팅 전송 가능 여부 (연결 + 로그인)
    private var canSend: Bool { viewModel?.canSendChat ?? false }

    /// 자동완성 활성 여부
    private var isAutocompleteActive: Bool { viewModel?.isAutocompleteActive ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // 로그인 안내 배너 — Glass (미로그인 또는 Read-only 연결 시)
            if let vm = viewModel, vm.connectionState.isConnected, !canSend {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(DesignTokens.Typography.caption)
                    Text("로그인하면 채팅에 참여할 수 있어요")
                        .font(DesignTokens.Typography.caption)
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(DesignTokens.Colors.surfaceElevated)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DesignTokens.Colors.border.opacity(0.15))
                        .frame(height: 0.5)
                }
            }

            // 자동완성 팝업 (입력창 위)
            if let vm = viewModel, isAutocompleteActive {
                ChatAutocompleteView(viewModel: vm) { index in
                    applyAutocomplete(at: index)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(DesignTokens.Animation.fast, value: isAutocompleteActive)
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                // Emoticon button — Glass circle (컴팩트 모드에서는 숨김)
                if !compact {
                Button {
                    showEmoticonPicker.toggle()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(showEmoticonPicker ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            isEmoticonHovered && canSend
                                ? DesignTokens.Colors.surfaceElevated.opacity(1.2)
                                : DesignTokens.Colors.surfaceElevated,
                            in: Circle()
                        )
                        .overlay {
                            Circle().strokeBorder(
                                isEmoticonHovered && canSend
                                    ? DesignTokens.Colors.chzzkGreen.opacity(0.3)
                                    : DesignTokens.Glass.borderColorLight,
                                lineWidth: 0.5
                            )
                        }
                        .scaleEffect(isEmoticonHovered && canSend ? 1.06 : 1.0)
                        .animation(DesignTokens.Animation.fast, value: isEmoticonHovered)
                }
                .buttonStyle(.plain)
                .onHover { hovering in isEmoticonHovered = hovering }
                .popover(isPresented: $showEmoticonPicker) {
                    EmoticonPickerView(packs: viewModel?.emoticonPickerPacks ?? []) { emoticon in
                        inputText += emoticon.chatPattern
                        showEmoticonPicker = false
                    }
                }
                .help("이모티콘")
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)
                } // if !compact

                // Glass 입력 필드
                HStack(spacing: 8) {
                    if !compact {
                    Image(systemName: canSend ? "text.bubble" : "lock")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(isFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                    }

                    TextField(placeholderText, text: $inputText)
                        .textFieldStyle(.plain)
                        .font(compact ? DesignTokens.Typography.custom(size: 11, weight: .regular) : DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .focused($isFocused)
                        .onSubmit {
                            if isAutocompleteActive {
                                applyAutocomplete(at: viewModel?.autocompleteSelectedIndex ?? 0)
                            } else {
                                sendMessage()
                            }
                        }
                        .disabled(!canSend)
                        .onChange(of: inputText) { _, newValue in
                            viewModel?.updateAutocompleteSuggestions(for: newValue)
                        }
                }
                .padding(.horizontal, compact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
                .padding(.vertical, compact ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.xs)
                // [GPU 최적화] Material blur → 솔리드 반투명 색상으로 교체
                // ultraThinMaterial은 비디오 레이어 변경 시 매 프레임 blur 재계산 → GPU 부하
                .background(DesignTokens.Colors.surfaceBase.opacity(0.85), in: RoundedRectangle(cornerRadius: compact ? DesignTokens.Radius.sm : DesignTokens.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(
                            isFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.55) : DesignTokens.Glass.borderColorLight,
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                }
                .shadow(color: isFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.18) : .clear, radius: 8)
                .animation(DesignTokens.Animation.fast, value: isFocused)
                .onTapGesture { if canSend { isFocused = true } }

                // 전송 버튼 — Pill 느낌의 원형
                let isReady = canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(compact ? DesignTokens.Typography.custom(size: 10, weight: .semibold) : DesignTokens.Typography.captionMedium)
                        .foregroundStyle(isReady ? .black : DesignTokens.Colors.textTertiary)
                        .frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
                        .background(
                            isReady
                                ? AnyShapeStyle(DesignTokens.Colors.chzzkGreen)
                                : AnyShapeStyle(DesignTokens.Colors.surfaceElevated)
                        )
                        .clipShape(Circle())
                        .overlay {
                            if !isReady {
                                Circle().strokeBorder(
                                    isSendHovered ? DesignTokens.Colors.textTertiary.opacity(0.3) : DesignTokens.Glass.borderColorLight,
                                    lineWidth: 0.5
                                )
                            }
                        }
                        .shadow(color: isReady ? DesignTokens.Colors.chzzkGreen.opacity(0.3) : .clear, radius: 6)
                        .scaleEffect(isSendHovered && isReady ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in isSendHovered = hovering }
                .disabled(!isReady)
                .animation(DesignTokens.Animation.fast, value: isReady)
                .animation(DesignTokens.Animation.fast, value: isSendHovered)
            }
            .padding(.horizontal, compact ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
            .padding(.vertical, compact ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.sm)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Glass.dividerColor)
                    .frame(height: 0.5)
            }
        }
        .onKeyPress(.upArrow) {
            guard isAutocompleteActive else { return .ignored }
            viewModel?.moveAutocompleteSelection(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isAutocompleteActive else { return .ignored }
            viewModel?.moveAutocompleteSelection(delta: 1)
            return .handled
        }
        .onKeyPress(.tab) {
            guard isAutocompleteActive else { return .ignored }
            applyAutocomplete(at: viewModel?.autocompleteSelectedIndex ?? 0)
            return .handled
        }
        .onKeyPress(.escape) {
            guard isAutocompleteActive else { return .ignored }
            viewModel?.dismissAutocomplete()
            return .handled
        }
    }

    /// 컴팩트/일반 모드별 placeholder 텍스트
    private var placeholderText: String {
        if !canSend { return compact ? "로그인 필요" : "로그인 후 채팅 참여 가능" }
        if compact {
            if let hint = compactChannelHint, !hint.isEmpty { return "→ \(hint)" }
            return "메시지..."
        }
        return "채팅을 입력하세요..."
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, canSend else { return }
        viewModel?.dismissAutocomplete()
        inputText = ""
        viewModel?.inputText = text
        Task {
            await viewModel?.sendMessage()
            await MainActor.run { viewModel?.inputText = "" }
        }
    }

    /// 자동완성 항목 적용
    private func applyAutocomplete(at index: Int) {
        guard let vm = viewModel,
              let result = vm.applyAutocompletion(to: inputText, selectedIndex: index) else { return }
        inputText = result
    }
}
