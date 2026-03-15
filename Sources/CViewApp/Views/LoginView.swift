// MARK: - LoginView.swift
// CViewApp - 통합 로그인 뷰 (네이버 쿠키 + 치지직 OAuth)

import SwiftUI
import CViewCore
import CViewAuth

// MARK: - Login Method

private enum LoginMethod: String, CaseIterable {
    case chzzkOAuth = "치지직 OAuth"
    case naverCookie = "네이버 로그인"
}

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var loginError: String?
    @State private var selectedMethod: LoginMethod = .chzzkOAuth
    @State private var isOAuthLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Branded header
            loginHeader
            
            // Separator
            Divider()
            
            // Login method picker
            Picker("", selection: $selectedMethod) {
                ForEach(LoginMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            
            // Content area
            switch selectedMethod {
            case .chzzkOAuth:
                oauthLoginContent
            case .naverCookie:
                cookieLoginContent
            }
            
            // Error bar
            if let error = loginError {
                errorBar(error)
            }
        }
        .frame(width: 500, height: 660)
        .background(DesignTokens.Colors.background)
    }
    
    // MARK: - Header
    
    private var loginHeader: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(DesignTokens.Gradients.primary)
                            .frame(width: 28, height: 28)
                        
                        Text("C")
                            .font(DesignTokens.Typography.custom(size: 15, weight: .black))
                            .foregroundStyle(DesignTokens.Colors.onPrimary)
                    }
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 5, y: 2)
                    
                    Text("CView 로그인")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DesignTokens.Colors.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            Text("로그인하여 팔로잉, 채팅 등 모든 기능을 이용하세요")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.background)
    }
    
    // MARK: - OAuth Login
    
    private var oauthLoginContent: some View {
        VStack(spacing: 0) {
            if isOAuthLoading {
                // OAuth WebView로 인증 중
                oauthWebViewContent
            } else {
                // OAuth 시작 화면
                oauthStartContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var oauthStartContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
            
            // Chzzk 아이콘
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(DesignTokens.Typography.custom(size: 36))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            }
            
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("치지직 OAuth 로그인")
                    .font(DesignTokens.Typography.custom(size: 18, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                
                Text("치지직 공식 인증을 통해\n안전하게 로그인합니다")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // OAuth 장점 안내
            VStack(alignment: .leading, spacing: 8) {
                oauthBenefitRow(icon: "lock.shield", text: "비밀번호를 직접 입력하지 않습니다")
                oauthBenefitRow(icon: "arrow.triangle.2.circlepath", text: "자동 토큰 갱신으로 로그인 유지")
                oauthBenefitRow(icon: "bolt.fill", text: "공식 API로 빠르고 안정적")
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            
            Spacer()
            
            // 로그인 버튼
            Button {
                startOAuthLogin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 16))
                    Text("치지직으로 로그인")
                        .font(DesignTokens.Typography.bodySemibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(DesignTokens.Colors.chzzkGreen)
                .foregroundStyle(DesignTokens.Colors.onPrimary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }
    
    private func oauthBenefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                .frame(width: 20)
            
            Text(text)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
    
    @State private var oauthAuthURL: URL?
    
    private var oauthWebViewContent: some View {
        Group {
            if let authURL = oauthAuthURL {
                OAuthLoginWebView(
                    authURL: authURL,
                    redirectURI: OAuthConfig.chzzk.redirectURI,
                    onCodeReceived: { code, _ in
                        Task { @MainActor in
                            handleOAuthCode(code)
                        }
                    },
                    onError: { error in
                        Task { @MainActor in
                            loginError = error
                            isOAuthLoading = false
                        }
                    }
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("인증 준비 중...")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Cookie Login (기존 네이버 로그인)
    
    private var cookieLoginContent: some View {
        LoginWebView(
            onLoginSuccess: {
                Task {
                    await appState.handleLoginSuccess()
                }
                dismiss()
            },
            onLoginFailed: { error in
                loginError = error
            }
        )
    }
    
    // MARK: - Error Bar
    
    private func errorBar(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.error)
            
            Text(error)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.error)
            
            Spacer()
            
            Button {
                loginError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.error.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceBase)
    }
    
    // MARK: - OAuth Actions
    
    private func startOAuthLogin() {
        loginError = nil
        isOAuthLoading = true
        
        Task {
            guard let authManager = getAuthManager() else {
                loginError = "인증 관리자 초기화 실패"
                isOAuthLoading = false
                return
            }
            
            guard let url = await authManager.oauthService.generateAuthURL() else {
                loginError = "OAuth URL 생성 실패"
                isOAuthLoading = false
                return
            }
            
            oauthAuthURL = url
        }
    }
    
    private func handleOAuthCode(_ code: String) {
        Task { @MainActor in
            guard let authManager = getAuthManager() else {
                loginError = "인증 관리자를 찾을 수 없습니다"
                isOAuthLoading = false
                return
            }
            
            do {
                try await authManager.handleOAuthLoginSuccess(code: code)
                await appState.handleOAuthLoginSuccess()
                dismiss()
            } catch {
                loginError = "OAuth 로그인 실패: \(error.localizedDescription)"
                isOAuthLoading = false
                oauthAuthURL = nil
            }
        }
    }
    
    private func getAuthManager() -> AuthManager? {
        // AppState에서 authManager 접근
        appState.getAuthManager()
    }
}
