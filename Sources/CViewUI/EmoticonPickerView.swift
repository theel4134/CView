// MARK: - EmoticonPickerView.swift
// CViewUI — 채팅 입력창 이모티콘 선택기

import SwiftUI
import CViewCore

// MARK: - EmoticonPickerView

/// 채팅 입력창 하단에 표시되는 이모티콘 선택 패널
public struct EmoticonPickerView: View {
    public let packs: [EmoticonPack]
    public let onSelect: (EmoticonItem) -> Void

    @State private var selectedPackIndex: Int = 0
    @State private var searchText: String = ""

    private let columns = Array(repeating: GridItem(.fixed(52), spacing: 6), count: 6)

    public init(packs: [EmoticonPack], onSelect: @escaping (EmoticonItem) -> Void) {
        self.packs = packs
        self.onSelect = onSelect
    }

    // 검색 필터 적용된 이모티콘 목록
    private var filteredEmoticons: [EmoticonItem] {
        // 검색어 있으면 전체 팩에서 검색
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            return packs.flatMap { $0.emoticons ?? [] }.filter {
                ($0.emoticonName?.lowercased().contains(q) ?? false) ||
                $0.emoticonId.lowercased().contains(q)
            }
        }
        // 검색어 없으면 선택된 팩
        guard selectedPackIndex < packs.count else { return [] }
        return packs[selectedPackIndex].emoticons ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── 검색바 ─────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("이모티콘 검색", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DesignTokens.Colors.surface.opacity(0.5))

            Divider().background(DesignTokens.Colors.border.opacity(0.4))

            // ── 팩 탭 바 ──────────────────────────────────────────
            packTabBar

            Divider()
                .background(DesignTokens.Colors.border.opacity(0.4))

            // ── 이모티콘 그리드 ──────────────────────────────────────
            emoticonGrid
        }
        .frame(width: 380, height: 340)
        .background(DesignTokens.Colors.backgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Pack Tab Bar

    private var packTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(packs.enumerated()), id: \.offset) { idx, pack in
                    packTab(pack: pack, index: idx)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 50)
        .background(DesignTokens.Colors.surface.opacity(0.6))
    }

    @ViewBuilder
    private func packTab(pack: EmoticonPack, index: Int) -> some View {
        let isSelected = selectedPackIndex == index
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPackIndex = index
            }
        } label: {
            Group {
                if let imgURL = pack.emoticonPackImageURL {
                    CachedAsyncImage(url: imgURL) {
                        packTabPlaceholder(pack)
                    }
                    .scaledToFill()
                } else {
                    packTabPlaceholder(pack)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? DesignTokens.Colors.chzzkGreen : Color.clear,
                        lineWidth: 2
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.12)
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(pack.emoticonPackName)
    }

    @ViewBuilder
    private func packTabPlaceholder(_ pack: EmoticonPack) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignTokens.Colors.surface)
            Text(String(pack.emoticonPackName.prefix(1)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - Emoticon Grid

    @ViewBuilder
    private var emoticonGrid: some View {
        if packs.isEmpty {
            emptyState(text: "이모티콘 없음", sub: "이 채널에 이모티콘이 없습니다")
        } else if filteredEmoticons.isEmpty {
            emptyState(text: "검색 결과 없음", sub: "다른 키워드로 검색해 보세요")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(filteredEmoticons) { item in
                        emoticonCell(item)
                    }
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private func emoticonCell(_ item: EmoticonItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            Group {
                if let url = item.imageURL {
                    CachedAsyncImage(url: url) {
                        cellPlaceholder
                    }
                    .scaledToFit()
                } else {
                    cellPlaceholder
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
        )
        .hoverEffect()
        .help(item.emoticonName ?? item.emoticonId)
    }

    private var cellPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(DesignTokens.Colors.surface.opacity(0.6))
            .overlay {
                ProgressView()
                    .scaleEffect(0.6)
            }
    }

    @ViewBuilder
    private func emptyState(text: String, sub: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "face.smiling")
                .font(.system(size: 28))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - hoverEffect helper (NSView-based highlight)

private extension View {
    @ViewBuilder
    func hoverEffect() -> some View {
        self.modifier(HoverHighlightModifier())
    }
}

private struct HoverHighlightModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered
                        ? DesignTokens.Colors.surface.opacity(0.8)
                        : Color.clear)
            )
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
