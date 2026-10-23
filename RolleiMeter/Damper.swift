import Foundation
import QuartzCore

/// Spring-damped values, stepped by the display link. Gives readings and markers
/// the slightly weighted, settling feel of a needle instead of snapping.
///
/// Held in `@State` (not `@StateObject`) by the parent so only views that
/// observe it re-render at 60 fps, not the whole screen.
final class Damper: NSObject, ObservableObject {
    @Published private(set) var values: [Double]

    private var targets: [Double]
    private var velocities: [Double]
    private let stiffness: Double
    private let damping: Double
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    /// Damping ratio is `damping / (2 * sqrt(stiffness))`. Around 0.7 settles with a hint of overshoot.
    init(count: Int, initial: Double = 0, stiffness: Double = 80, damping: Double = 13) {
        values = Array(repeating: initial, count: count)
        targets = Array(repeating: initial, count: count)
        velocities = Array(repeating: 0, count: count)
        self.stiffness = stiffness
        self.damping = damping
        super.init()
    }

    deinit { link?.invalidate() }

    func set(_ new: [Double], snap: Bool = false) {
        guard new.count == targets.count else { return }
        targets = new
        if snap {
            values = new
            velocities = Array(repeating: 0, count: new.count)
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard link == nil else { return }
        last = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        if #available(iOS 15.0, *) {
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = last == 0 ? 1.0 / 60.0 : min(now - last, 1.0 / 20.0)
        last = now

        var v = values
        var settled = true
        for i in v.indices {
            let accel = stiffness * (targets[i] - v[i]) - damping * velocities[i]
            velocities[i] += accel * dt
            v[i] += velocities[i] * dt
            if abs(targets[i] - v[i]) > 0.0005 || abs(velocities[i]) > 0.0005 { settled = false }
        }
        if settled {
            v = targets
            velocities = Array(repeating: 0, count: v.count)
            stop()
        }
        values = v
    }
}
