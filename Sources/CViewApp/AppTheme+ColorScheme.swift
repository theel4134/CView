// MARK: - AppTheme+ColorScheme.swift
// AppTheme extension - SwiftUI ColorScheme conversion

import SwiftUI
import CViewCore

// MARK: - AppTheme + SwiftUI ColorScheme

extension AppTheme {
    /// SwiftUI preferredColorScheme 값으로 변환 (nil = 시스템 따름)
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}
