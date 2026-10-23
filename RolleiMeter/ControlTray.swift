import SwiftUI
import UIKit

/// The few settings that aren't part of shooting: film speed units, distance units,
/// meter calibration and the arm-length offset. Shown over the viewfinder.
struct ControlTray: View {
    @Binding var useDIN: Bool
    @Binding var useFeet: Bool
    @Binding var calibration: Double
    @Binding var armOffset: Double
    let rawDistance: () -> Double?
    let onClose: () -> Void

    @State private var armStage = 0
    @State private var armCountdown = 4
    @State private var armTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            row("FILM SPEED") { EngravedChoice(options: ["ISO", "DIN"], selection: boolBinding($useDIN)) }
            divider
            row("DISTANCE") { EngravedChoice(options: ["M", "FT"], selection: boolBinding($useFeet)) }
            divider
            row("CALIBRATE") {
                MiniStepper(
                    text: Fmt.stops(calibration) + " EV",
                    onMinus: { stepCalibration(-1) },
                    onPlus: { stepCalibration(1) }
                )
            }
            divider
            row("ARM") {
                HStack(spacing: 6) {
                    MiniStepper(
                        text: Fmt.distance(armOffset, feet: useFeet),
                        onMinus: { stepArm(-1) },
                        onPlus: { stepArm(1) }
                    )
                    armButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 380)
        .onDisappear {
            armTask?.cancel()
            armStage = 0
            armCountdown = 4
        }
    }

    private var header: some View {
        HStack {
            Text("SETTINGS")
                .font(AppTypography.next(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Palette.text)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.dim)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
        }
        .padding(.bottom, 4)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(Palette.dim)
            Spacer(minLength: 8)
            content()
        }
        .frame(height: 32)
    }

    private func boolBinding(_ source: Binding<Bool>) -> Binding<Int> {
        Binding(get: { source.wrappedValue ? 1 : 0 }, set: { source.wrappedValue = ($0 == 1) })
    }

    private func stepCalibration(_ direction: Int) {
        let next = calibration + Double(direction) / 3.0
        calibration = min(max((next * 3).rounded() / 3, -3), 3)
    }

    private func stepArm(_ direction: Int) {
        let next = armOffset + Double(direction) * 0.05
        armOffset = min(max((next * 100).rounded() / 100, 0), 0.8)
    }

    private var armButton: some View {
        Button {
            startArmCalibration()
        } label: {
            Text(armStage == 0 ? "SET" : "HOLD AT EYE \u{00B7} \(armCountdown)")
                .font(AppTypography.next(size: 11, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.18), value: armCountdown)
                .animation(.smooth(duration: 0.18), value: armStage)
                .tracking(0.8)
                .foregroundStyle(armStage == 0 ? Palette.text : Palette.accent)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background {
                    if #available(iOS 26.0, *) {
                        EmptyView()
                    } else {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(armStage != 0)
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

struct EngravedChoice: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    guard selection != i else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.25)) { selection = i }
                } label: {
                    Text(options[i])
                        .font(AppTypography.font(size: 11, weight: selection == i ? .bold : .regular))
                        .foregroundStyle(selection == i ? Palette.accent : Palette.dim)
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) {
                            if selection == i {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "choiceUnderline", in: underlineNamespace)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MiniStepper: View {
    let text: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", label: "Decrease", action: onMinus)
            Text(text)
                .font(AppTypography.font(size: 12, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(minWidth: 54)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.15), value: text)
            stepButton("plus", label: "Increase", action: onPlus)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
