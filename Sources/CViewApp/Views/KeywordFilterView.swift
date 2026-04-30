// MARK: - KeywordFilterView.swift
// CViewApp - 채팅 키워드 필터 & 차단 관리 뷰

import SwiftUI
import CViewCore
import CViewChat

/// 채팅 키워드 필터 관리 뷰
struct KeywordFilterView: View {
    
    @Environment(AppState.self) private var appState
    @State private var newKeyword = ""
    @State private var keywords: [String] = []
    @State private var blockedUserIds: [String] = []
    @State private var newBlockUserId = ""
    @State private var selectedTab: FilterTab = .keywords
    @State private var isFilterEnabled = true
    
    enum FilterTab: String, CaseIterable, Identifiable {
        case keywords = "키워드"
        case users = "사용자"
        
        var id: String { rawValue }
    }
    
    private var chatVM: ChatViewModel? { appState.chatViewModel }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("채팅 필터")
                    .font(.headline)
                Spacer()
                Toggle("필터 활성화", isOn: $isFilterEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(DesignTokens.Spacing.md)            
            // Tab picker
            Picker("필터 유형", selection: $selectedTab) {
                ForEach(FilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignTokens.Spacing.md)
            
            Divider()
                .padding(.top, DesignTokens.Spacing.sm)
            
            // Content
            switch selectedTab {
            case .keywords:
                keywordSection
            case .users:
                userSection
            }
        }
        .frame(width: 340, height: 400)
        .onAppear {
            isFilterEnabled = appState.settingsStore.chat.chatFilterEnabled
            keywords = appState.settingsStore.chat.blockedWords
            Task {
                let blocked = await chatVM?.getBlockedUsers() ?? []
                blockedUserIds = Array(blocked).sorted()
            }
        }
        .onChange(of: isFilterEnabled) { _, newValue in
            appState.settingsStore.chat.chatFilterEnabled = newValue
            Task { await appState.settingsStore.save() }
            if newValue {
                Task { await chatVM?.addKeywordFilter(keywords) }
            }
        }
    }
    
    // MARK: - Keyword Section
    
    private var keywordSection: some View {
        VStack(spacing: 0) {
            // Add keyword input
            HStack(spacing: 8) {
                TextField("차단할 키워드 입력", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Typography.caption)
                    .onSubmit { addKeyword() }
                
                Button {
                    addKeyword()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(DesignTokens.Spacing.md)
            
            Divider()
            
            // Keyword list
            if keywords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.xmark")
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(.tertiary)
                    Text("등록된 키워드가 없습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("차단할 키워드를 추가하면\n해당 키워드가 포함된 메시지가 숨겨집니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(keywords, id: \.self) { keyword in
                        HStack {
                            Image(systemName: "text.word.spacing")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.warning)
                            
                            Text(keyword)
                                .font(DesignTokens.Typography.caption)
                            
                            Spacer()
                            
                            Button {
                                removeKeyword(keyword)
                            } label: {
                                Image(systemName: "trash")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.error)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            
            // Footer
            HStack {
                Text("\(keywords.count)개 키워드")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("전체 삭제") {
                    keywords.removeAll()
                    Task { await updateFilters() }
                }
                .font(.caption2)
                .disabled(keywords.isEmpty)
            }
            .padding(DesignTokens.Spacing.sm)
        }
    }
    
    // MARK: - User Section
    
    private var userSection: some View {
        VStack(spacing: 0) {
            // Add user input
            HStack(spacing: 8) {
                TextField("차단할 사용자 ID", text: $newBlockUserId)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Typography.caption)
                    .onSubmit { addBlockedUser() }
                
                Button {
                    addBlockedUser()
                } label: {
                    Image(systemName: "person.fill.badge.minus")
                        .font(DesignTokens.Typography.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.error)
                .disabled(newBlockUserId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(DesignTokens.Spacing.md)
            
            Divider()
            
            // Blocked user list
            if blockedUserIds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(.tertiary)
                    Text("차단된 사용자가 없습니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(blockedUserIds, id: \.self) { userId in
                        HStack {
                            Image(systemName: "person.fill")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.error)
                            
                            Text(userId)
                                .font(DesignTokens.Typography.custom(size: 12, design: .monospaced))
                            
                            Spacer()
                            
                            Button("해제") {
                                unblockUser(userId)
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            
            // Footer
            HStack {
                Text("\(blockedUserIds.count)명 차단")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(DesignTokens.Spacing.sm)
        }
    }
    
    // MARK: - Actions
    
    private func addKeyword() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, !keywords.contains(keyword) else { return }
        keywords.append(keyword)
        newKeyword = ""
        appState.settingsStore.chat.blockedWords = keywords
        Task {
            await appState.settingsStore.save()
            await updateFilters()
        }
    }
    
    private func removeKeyword(_ keyword: String) {
        keywords.removeAll { $0 == keyword }
        appState.settingsStore.chat.blockedWords = keywords
        Task {
            await appState.settingsStore.save()
            await updateFilters()
        }
    }
    
    private func addBlockedUser() {
        let userId = newBlockUserId.trimmingCharacters(in: .whitespaces)
        guard !userId.isEmpty, !blockedUserIds.contains(userId) else { return }
        blockedUserIds.append(userId)
        newBlockUserId = ""
        Task { await chatVM?.blockUser(userId) }
    }
    
    private func unblockUser(_ userId: String) {
        blockedUserIds.removeAll { $0 == userId }
        Task { await chatVM?.unblockUser(userId) }
    }
    
    private func updateFilters() async {
        await chatVM?.addKeywordFilter(keywords)
    }
}

// MARK: - Chat Export View

/// 채팅 로그 내보내기 뷰
struct ChatExportView: View {
    
    @Environment(AppState.self) private var appState
    @State private var exportFormat: ExportFormat = .text
    @State private var isExporting = false
    @State private var exportResult: String?
    @State private var includeNormal = true
    @State private var includeDonation = true
    @State private var includeSubscription = true
    @State private var includeSystem = false
    @Environment(\.dismiss) private var dismiss
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case text = "텍스트 (.txt)"
        case json = "JSON (.json)"
        case csv = "CSV (.csv)"
        
        var id: String { rawValue }
        
        var fileExtension: String {
            switch self {
            case .text: "txt"
            case .json: "json"
            case .csv: "csv"
            }
        }
    }
    
    private var chatVM: ChatViewModel? { appState.chatViewModel }
    
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("채팅 로그 내보내기")
                    .font(.headline)
            }
            
            // Stats
            HStack(spacing: DesignTokens.Spacing.lg) {
                statBox("총 메시지", value: "\(exportSourceMessages.count)")
                statBox("일반", value: "\(exportSourceMessages.filter { !$0.isSystem && !$0.isNotice }.count)")
                statBox("후원", value: "\(exportSourceMessages.filter { $0.donationAmount != nil }.count)")
            }
            
            Divider()
            
            // Format picker
            VStack(alignment: .leading, spacing: 8) {
                Text("내보내기 형식")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("형식", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            Divider()
            
            // Message type filter
            VStack(alignment: .leading, spacing: 8) {
                Text("포함할 메시지 유형")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: DesignTokens.Spacing.md) {
                    Toggle("일반", isOn: $includeNormal)
                    Toggle("후원", isOn: $includeDonation)
                    Toggle("구독", isOn: $includeSubscription)
                    Toggle("시스템", isOn: $includeSystem)
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                
                let filteredCount = filteredMessages.count
                Text("선택된 메시지: \(filteredCount)개")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Export result
            if let result = exportResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.success)
                    .padding(DesignTokens.Spacing.xs)
                    .background(DesignTokens.Colors.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
            
            // Actions
            HStack {
                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    Task { await exportChat() }
                } label: {
                    HStack(spacing: 6) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("내보내기")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.chzzkGreen)
                .disabled(isExporting || exportSourceMessages.isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 380)
    }
    
    // MARK: - Stat Box
    
    private func statBox(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(DesignTokens.Typography.custom(size: 18, weight: .bold, design: .monospaced))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }
    
    // MARK: - Export
    
    /// All messages available for export — prefer full history if populated.
    private var exportSourceMessages: [ChatMessageItem] {
        if let history = chatVM?.chatHistory, !history.isEmpty {
            return history
        }
        return chatVM?.messages.toArray() ?? []
    }

    private var filteredMessages: [ChatMessageItem] {
        return exportSourceMessages.filter { msg in
            if msg.isSystem { return includeSystem }
            if msg.type == MessageType.donation { return includeDonation }
            if msg.type == MessageType.subscription { return includeSubscription }
            return includeNormal
        }
    }
    
    private func exportChat() async {
        let messages = filteredMessages
        guard !messages.isEmpty else { return }
        isExporting = true
        defer { isExporting = false }
        
        let content: String
        switch exportFormat {
        case .text:
            content = messages.map { msg in
                "[\(msg.formattedTime)] \(msg.nickname): \(msg.content)"
            }.joined(separator: "\n")
            
        case .json:
            let entries = messages.map { msg -> [String: Any] in
                var entry: [String: Any] = [
                    "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                    "nickname": msg.nickname,
                    "content": msg.content,
                    "userId": msg.userId
                ]
                if let amount = msg.donationAmount {
                    entry["donationAmount"] = amount
                }
                return entry
            }
            if let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) {
                content = String(data: data, encoding: .utf8) ?? "[]"
            } else {
                content = "[]"
            }
            
        case .csv:
            let header = "Timestamp,Nickname,Content,Type,Donation"
            let rows = messages.map { msg -> String in
                let escapedContent = msg.content.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(msg.formattedTime)\",\"\(msg.nickname)\",\"\(escapedContent)\",\"\(msg.type.rawValue)\",\"\(msg.donationAmount.map(String.init) ?? "")\""
            }
            content = ([header] + rows).joined(separator: "\n")
        }
        
        // NSSavePanel
        await MainActor.run {
            let panel = NSSavePanel()
            panel.title = "채팅 로그 저장"
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "chat_log.\(exportFormat.fileExtension)"
            panel.canCreateDirectories = true
            
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    exportResult = "✓ \(messages.count)개 메시지를 저장했습니다"
                } catch {
                    exportResult = "✗ 저장 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}
