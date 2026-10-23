import UIKit
import ImageIO

/// How the (always landscape) sensor buffer is rotated to match the screen.
enum ViewRotation: Equatable {
    case landscapeRight   // sensor native, no rotation
    case landscapeLeft    // 180°
    case portrait         // 90° clockwise

    init(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .landscapeLeft: self = .landscapeLeft
        case .portrait, .portraitUpsideDown: self = .portrait
        default: self = .landscapeRight
        }
    }

    var isPortrait: Bool { self == .portrait }

    /// Angle for AVCaptureConnection.videoRotationAngle.
    var videoAngle: CGFloat {
        switch self {
        case .landscapeRight: return 0
        case .landscapeLeft: return 180
        case .portrait: return 90
        }
    }

    /// Orientation to apply to a sensor-space CIImage so it matches the screen.
    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .landscapeRight: return .up
        case .landscapeLeft: return .down
        case .portrait: return .right
        }
    }

    /// Width / height of the full camera frame as shown on screen.
    var frameAspect: CGFloat { isPortrait ? 3.0 / 4.0 : 4.0 / 3.0 }

    /// Converts a normalized point in the on-screen full frame to sensor-buffer space.
    func toBuffer(_ p: CGPoint) -> CGPoint {
        switch self {
        case .landscapeRight: return p
        case .landscapeLeft: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        case .portrait: return CGPoint(x: p.y, y: 1 - p.x)
        }
    }
}
