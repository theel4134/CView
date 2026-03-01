// MARK: - MultiLiveAddSheet.swift  
// CViewApp — 멀티라이브 채널 추가 시트
// 라이브 검색 + 채널 ID 직접 입력

import SwiftUI
import CViewCore
import CViewNetworking

struct MultiLiveAddSheet: View {

    @Bindable var manager: MultiLiveManager
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [LiveInfo] = []
    @State private var isSearching = false
    @State private var channelIdInput = ""
    @State private var addError: String?
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            header

            Divider()

            // 콘텐츠
            VStack(spacing: DesignTokens.Spacing.lg) {
                // 라이브 검색
                searchSection

                Divider()

                // 채널 ID 직접 입력
                directInputSection

                // 에러 메시지
                if let error = addError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .frame(width: 420, height: 500)
        .background(DesignTokens.Colors.backgroundElevated)
    }

    // MARK: - 헤더

    private var header: some View {
        HStack {
            Text("채널 추가")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            Text("\(manager.sessions.count)/\(MultiLiveManager.maxSessions)")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.08)))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.md)
    }

    // MARK: - 라이브 검색

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("라이브 검색")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("채널명 또는 방송 제목", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { searchLive() }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.surfaceBase)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacity), lineWidth: 0.5)
            }

            // 검색 결과
            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(searchResults) { live in
                            liveSearchRow(live: live)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - 검색 결과 행

    private func liveSearchRow(live: LiveInfo) -> some View {
        let alreadyAdded = manager.sessions.contains { $0.channelId == (live.channel?.channelId ?? "") }
        let channelId = live.channel?.channelId ?? ""

        return HStack(spacing: DesignTokens.Spacing.sm) {
            // 썸네일
            AsyncImage(url: live.channel?.channelImageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(live.channel?.channelName ?? "알 수 없음")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                Text(live.liveTitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                Text("\(live.concurrentUserCount)")
            }
            .font(.caption2)
            .foregroundStyle(DesignTokens.Colors.textTertiary)

            Button {
                guard !channelId.isEmpty else { return }
                addChannel(channelId: channelId)
            } label: {
                Text(alreadyAdded ? "추가됨" : "추가")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(alreadyAdded || !manager.canAddSession)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: - 직접 입력

    private var directInputSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("채널 ID 직접 입력")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("채널 ID", text: $channelIdInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                Button {
                    let id = channelIdInput.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    addChannel(channelId: id)
                } label: {
                    if isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("추가")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.chzzkGreen)
                .controlSize(.small)
                .disabled(channelIdInput.trimmingCharacters(in: .whitespaces).isEmpty || isAdding || !manager.canAddSession)
            }
        }
    }

    // MARK: - Actions

    private func searchLive() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let apiClient = appState.apiClient else { return }
        isSearching = true
        addError = nil

        Task {
            do {
                let result = try await apiClient.searchLives(keyword: query, size: 10)
                searchResults = result.data
            } catch {
                searchResults = []
                addError = "검색 실패: \(error.localizedDescription)"
            }
            isSearching = false
        }
    }

    private func addChannel(channelId: String) {
        isAdding = true
        addError = nil

        Task {
            await manager.addSession(channelId: channelId)
            isAdding = false
            channelIdInput = ""

            // 자동 닫기 (최대 세션 도달 시)
            if !manager.canAddSession {
                dismiss()
            }
        }
    }
}
