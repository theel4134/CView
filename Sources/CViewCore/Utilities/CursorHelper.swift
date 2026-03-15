import SwiftUI
import AppKit

extension View {
    @ViewBuilder
    public func customCursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active: cursor.push()
            case .ended:  NSCursor.pop()
            }
        }
    }
}
