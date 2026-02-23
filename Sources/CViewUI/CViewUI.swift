// MARK: - CViewUI Module
// 공유 UI 컴포넌트 & 디자인 시스템
// 향후 확장: 커스텀 컨트롤, 애니메이션, 테마 시스템

import SwiftUI
import CViewCore

// MARK: - Shared UI Components

/// 로딩 인디케이터 (브랜드 컬러)
public struct CViewLoadingIndicator: View {
    let message: String?
    
    public init(message: String? = nil) {
        self.message = message
    }
    
    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignTokens.Colors.chzzkGreen)
            
            if let message {
                Text(message)
                    .font(.system(size: DesignTokens.Typography.captionSize))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 라이브 뱃지
public struct LiveBadge: View {
    public init() {}
    
    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.red.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

/// 뷰어 카운트 뱃지
public struct ViewerCountBadge: View {
    let count: Int
    
    public init(count: Int) {
        self.count = count
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 9))
            Text(formattedCount)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    private var formattedCount: String {
        if count >= 10_000 {
            return String(format: "%.1f만", Double(count) / 10_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f천", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

/// 사용자 아바타
public struct UserAvatar: View {
    let imageUrl: String?
    let size: CGFloat
    
    public init(imageUrl: String?, size: CGFloat = 32) {
        self.imageUrl = imageUrl
        self.size = size
    }
    
    public var body: some View {
        CachedAsyncImage(url: URL(string: imageUrl ?? "")) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// 브랜드 버튼 스타일
public struct CViewButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.chzzkGreen)
            .foregroundStyle(.black)
            .fontWeight(.semibold)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
