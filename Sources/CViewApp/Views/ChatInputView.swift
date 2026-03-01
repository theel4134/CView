// MARK: - ChatInputView.swift
// CViewApp - 채팅 입력 영역 (이모티콘 · 자동완성 · 전송)

import SwiftUI
import CViewCore
import CViewChat
import CViewUI

// MARK: - Chat Input View (Premium)

struct ChatInputView: View {
    let viewModel: ChatViewModel?
    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var showEmoticonPicker = false

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
                .background(.ultraThinMaterial)
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
                // Emoticon button — Glass circle
                Button {
                    showEmoticonPicker.toggle()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(showEmoticonPicker ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmoticonPicker) {
                    EmoticonPickerView(packs: viewModel?.emoticonPickerPacks ?? []) { emoticon in
                        inputText += emoticon.chatPattern
                        showEmoticonPicker = false
                    }
                }
                .help("이모티콘")
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)

                // Glass 입력 필드
                HStack(spacing: 8) {
                    Image(systemName: canSend ? "text.bubble" : "lock")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(isFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)

                    TextField(canSend ? "채팅을 입력하세요..." : "로그인 후 채팅 참여 가능", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.captionMedium)
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
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(
                            isFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : .white.opacity(DesignTokens.Glass.borderOpacityLight),
                            lineWidth: isFocused ? 1 : 0.5
                        )
                }
                .shadow(color: isFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.1) : .clear, radius: 6)
                .animation(DesignTokens.Animation.fast, value: isFocused)
                .onTapGesture { if canSend { isFocused = true } }

                // 전송 버튼 — Pill 느낌의 원형
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .black : DesignTokens.Colors.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(
                            canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AnyShapeStyle(DesignTokens.Colors.chzzkGreen)
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                        .clipShape(Circle())
                        .overlay {
                            if !(canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty) {
                                Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                            }
                        }
                        .shadow(color: canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty ? DesignTokens.Colors.chzzkGreen.opacity(0.3) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                .animation(DesignTokens.Animation.fast, value: inputText.isEmpty)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(.thinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Colors.border.opacity(0.15))
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

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, canSend else { return }
        viewModel?.dismissAutocomplete()
        viewModel?.inputText = text
        inputText = ""
        Task { await viewModel?.sendMessage() }
        inputText = ""
    }

    /// 자동완성 항목 적용
    private func applyAutocomplete(at index: Int) {
        guard let vm = viewModel,
              let result = vm.applyAutocompletion(to: inputText, selectedIndex: index) else { return }
        inputText = result
    }
}
