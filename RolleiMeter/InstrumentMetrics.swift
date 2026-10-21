import SwiftUI

/// Shared proportions for the camera-inspired interface.
/// Phi is used for relationships between major shapes; square controls and
/// equal-spaced photographic scales stay square and evenly spaced.
enum InstrumentMetrics {
    static let phi: CGFloat = 1.61803398875

    /// Fibonacci-like spacing rhythm: 6, 10, 16 points.
    static let compactSpace: CGFloat = 6
    static var panelInset: CGFloat { compactSpace * phi }
    static var screenInset: CGFloat { compactSpace * phi * phi }

    /// Keep the side controls square; the shutter's outer ring is one phi larger.
    static let keySide: CGFloat = 46
    static var shutterOuterDiameter: CGFloat { keySide * phi }
    static var shutterCoreDiameter: CGFloat { shutterOuterDiameter / phi }

    /// Pair the viewfinder and paper-panel corners in the same proportion.
    static let panelCorner: CGFloat = 10
    static var viewfinderCorner: CGFloat { panelCorner * phi }

    /// Keep the compact EV arc's width proportional to its height.
    static let evGaugeHeight: CGFloat = 19
    static var evGaugeWidth: CGFloat { evGaugeHeight * phi }
}
