import SwiftUI
import UIKit

/// Standard iOS settings sheet: film speed units, distance units, meter calibration
/// and the arm-length offset.
struct SettingsSheet: View {
    @Binding var useDIN: Bool
    @Binding var useFeet: Bool
    @Binding var calibration: Double
    @Binding var armOffset: Double
    let rawDistance: () -> Double?

    @Environment(\.dismiss) private var dismiss
    @State private var armStage = 0
    @State private var armCountdown = 4
    @State private var armTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Film speed", selection: $useDIN) {
                        Text("ISO").tag(false)
                        Text("DIN").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Distance", selection: $useFeet) {
                        Text("Meters").tag(false)
                        Text("Feet").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper {
                        LabeledContent("Calibration", value: Fmt.stops(calibration) + " EV")
                    } onIncrement: {
                        stepCalibration(1)
                    } onDecrement: {
                        stepCalibration(-1)
                    }
                } header: {
                    Text("Light meter")
                } footer: {
                    Text("Shifts every reading, in third-stop steps.")
                }

                Section {
                    Stepper {
                        LabeledContent("Arm offset", value: Fmt.distance(armOffset, feet: useFeet))
                    } onIncrement: {
                        stepArm(1)
                    } onDecrement: {
                        stepArm(-1)
                    }
                    Button(action: startArmCalibration) {
                        Text(armStage == 0 ? "Measure arm length" : "Hold phone at your eye\u{2026} \(armCountdown)")
                            .contentTransition(.numericText())
                    }
                    .disabled(armStage != 0)
                } header: {
                    Text("Distance")
                } footer: {
                    Text("Measure: aim at a wall with the phone at arm\u{2019}s length, then pull it to your eye when asked.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            armTask?.cancel()
            armStage = 0
            armCountdown = 4
        }
    }

    private func stepCalibration(_ direction: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        let next = calibration + Double(direction) / 3.0
        calibration = min(max((next * 3).rounded() / 3, -3), 3)
    }

    private func stepArm(_ direction: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        let next = armOffset + Double(direction) * 0.05
        armOffset = min(max((next * 100).rounded() / 100, 0), 0.8)
    }

    private func startArmCalibration() {
        guard let first = rawDistance() else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        armStage = 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        armTask = Task { @MainActor in
            for remaining in stride(from: 4, through: 1, by: -1) {
                if Task.isCancelled { return }
                armCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            defer {
                armStage = 0
                armCountdown = 4
            }
            if Task.isCancelled { return }
            guard let second = rawDistance(), second > first + 0.05 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            armOffset = min(max(((second - first) * 100).rounded() / 100, 0), 0.8)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
