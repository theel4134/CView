// MARK: - ErrorRecoveryView.swift
// CViewApp - 재사용 가능한 에러 복구 뷰

import SwiftUI
import CViewCore

// MARK: - Error Category

enum AppErrorCategory: Sendable {
    case network
    case auth
    case stream
    case data
    case unknown
    
    var icon: String {
        switch self {
        case .network: "wifi.exclamationmark"
        case .auth: "lock.shield"
        case .stream: "play.slash"
        case .data: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }
    
    var title: String {
        switch self {
        case .network: "네트워크 오류"
        case .auth: "인증 오류"
        case .stream: "스트림 오류"
        case .data: "데이터 오류"
        case .unknown: "알 수 없는 오류"
        }
    }
    
    var color: Color {
        switch self {
        case .network: .orange
        case .auth: .red
        case .stream: .yellow
        case .data: .purple
        case .unknown: .gray
        }
    }
    
    static func from(_ error: Error) -> AppErrorCategory {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("network") || desc.contains("internet") || desc.contains("connection") ||
            desc.contains("timeout") || desc.contains("url") {
            return .network
        } else if desc.contains("auth") || desc.contains("login") || desc.contains("token") ||
                    desc.contains("unauthorized") || desc.contains("403") || desc.contains("401") {
            return .auth
        } else if desc.contains("stream") || desc.contains("media") || desc.contains("player") ||
                    desc.contains("hls") || desc.contains("vlc") {
            return .stream
        } else if desc.contains("data") || desc.contains("decode") || desc.contains("parse") ||
                    desc.contains("json") {
            return .data
        }
        return .unknown
    }
}

// MARK: - Error Recovery View

struct ErrorRecoveryView: View {
    let error: Error?
    let message: String?
    let category: AppErrorCategory
    let retryAction: (() async -> Void)?
    let dismissAction: (() -> Void)?
    
    @State private var isRetrying = false
    @State private var retryCount = 0
    
    init(
        error: Error? = nil,
        message: String? = nil,
        category: AppErrorCategory? = nil,
        retryAction: (() async -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        self.error = error
        self.message = message
        self.category = category ?? (error.map { AppErrorCategory.from($0) } ?? .unknown)
        self.retryAction = retryAction
        self.dismissAction = dismissAction
    }
    
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Icon
            Image(systemName: category.icon)
                .font(DesignTokens.Typography.custom(size: 48))
                .foregroundStyle(category.color)
                .symbolEffect(.bounce, value: retryCount)
            
            // Title
            Text(category.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            // Message
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            } else if let error {
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            // Suggestion
            Text(suggestion)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            // Actions
            HStack(spacing: DesignTokens.Spacing.md) {
                if let retryAction {
                    Button {
                        Task {
                            isRetrying = true
                            retryCount += 1
                            await retryAction()
                            isRetrying = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRetrying {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isRetrying ? "재시도 중..." : "다시 시도")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .disabled(isRetrying)
                }
                
                if let dismissAction {
                    Button("닫기") {
                        dismissAction()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Retry count
            if retryCount > 0 {
                Text("재시도 횟수: \(retryCount)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }
    
    private var suggestion: String {
        switch category {
        case .network:
            "인터넷 연결을 확인하고 다시 시도해 주세요."
        case .auth:
            "설정에서 다시 로그인해 주세요."
        case .stream:
            "방송이 종료되었거나 일시적인 오류일 수 있습니다."
        case .data:
            "잠시 후 다시 시도해 주세요. 문제가 지속되면 앱을 재시작해 보세요."
        case .unknown:
            "예상치 못한 오류가 발생했습니다. 다시 시도해 주세요."
        }
    }
}

// MARK: - Inline Error Banner

struct ErrorBanner: View {
    let message: String
    let category: AppErrorCategory
    var retryAction: (() -> Void)?
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                
                Text(message)
                    .font(DesignTokens.Typography.caption)
                    .lineLimit(2)
                
                Spacer()
                
                if let retryAction {
                    Button("재시도") {
                        retryAction()
                    }
                    .font(DesignTokens.Typography.captionMedium)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button {
                    withAnimation(DesignTokens.Animation.fast) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - View Extension for Error Handling

extension View {
    /// 에러 배너 오버레이
    func errorBanner(
        message: String,
        category: AppErrorCategory = .unknown,
        isVisible: Binding<Bool>,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        overlay(alignment: .top) {
            ErrorBanner(
                message: message,
                category: category,
                retryAction: retryAction,
                isVisible: isVisible
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
            .animation(DesignTokens.Animation.indicator, value: isVisible.wrappedValue)
        }
    }
}
