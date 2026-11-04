import SwiftUI
import UIKit

enum Metrics {
    static let gutter: CGFloat = 16
    static let minTap: CGFloat = 44
}

enum Haptics {
    static func tap() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func press() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
