import SwiftUI
import UIKit

/// One tray for everything adjustable, in the app's own paper UI: the exposure dials on one tab,
/// the rarely touched options on the other. No system sheet, no system form.
struct ControlTray: View {
    @Binding var evIndex: Int
    @Binding var isoIndex: Int
    @Binding var useDIN: Bool
    @Binding var useFeet: Bool
    @Binding var simpleMode: Bool
    @Binding var calibration: Double
    /// Metres between where the phone is held and where the Rollei's film plane sits (your eye).
    @Binding var armOffset: Double
    /// Latest raw LiDAR distance in metres, without the arm offset.
    let rawDistance: () -> Double?

    @State private var tab = 0
    /// 0 = idle, 1 = waiting for the phone to be moved to the eye.
    @State private var armStage = 0
    @State private var armCountdown = 4
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 4) {
            tabs
            if tab == 0 {
                dials
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            } else {
                options
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .modifier(Panel())
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 24) {
            tabButton("DIALS", 0)
            tabButton("OPTIONS", 1)
        }
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = index }
        } label: {
            Text(title)
                .font(AppTypography.next(size: 11, weight: tab == index ? .semibold : .regular))
                .tracking(1.1)
                .foregroundStyle(tab == index ? Palette.ink : Palette.mutedInk)
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    if tab == index {
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(height: 1.5)
                            .matchedGeometryEffect(id: "tabUnderline", in: tabNamespace)
                    }
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == index ? .isSelected : [])
    }

    // MARK: Dials

    private var dials: some View {
        HStack(spacing: 0) {
            ScrubDial(title: "EV", selection: $evIndex, labels: EVComp.labels, resetIndex: EVComp.zeroIndex)
            Rectangle().fill(Palette.hairline.opacity(0.7)).frame(width: 1).padding(.vertical, 8)
            ScrubDial(
                title: useDIN ? "DIN" : "ISO",
                selection: $isoIndex,
                labels: ISOScale.values.map { ISOScale.label($0, din: useDIN) },
                resetIndex: ISOScale.values.firstIndex(of: 100)
            )
        }
    }

    // MARK: Options

    private var options: some View {
        VStack(spacing: 0) {
            row("FILM SPEED") { EngravedChoice(options: ["ISO", "DIN"], selection: boolBinding($useDIN)) }
            divider
            row("DISTANCE") { EngravedChoice(options: ["M", "FT"], selection: boolBinding($useFeet)) }
            divider
            row("SIMPLE") { EngravedChoice(options: ["OFF", "ON"], selection: boolBinding($simpleMode)) }
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
                .padding(.trailing, 9)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline.opacity(0.7)).frame(height: 1)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.next(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(Palette.mutedInk)
            Spacer(minLength: 8)
            content()
        }
        .frame(height: 34)
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

    // MARK: Arm calibration

    /// Tap with the phone held the way you naturally hold it, then bring it to your eye and hold still.
    /// Four seconds later the second distance is read and the difference becomes the offset.
    private var armButton: some View {
        Button {
            startArmCalibration()
        } label: {
            Text(armStage == 0 ? "SET" : "HOLD AT EYE · \(armCountdown)")
                .font(AppTypography.next(size: 11, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.18), value: armCountdown)
                .animation(.smooth(duration: 0.18), value: armStage)
                .tracking(0.8)
                .foregroundStyle(armStage == 0 ? Palette.ink : Palette.accent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Palette.ink.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(armStage != 0)
        .accessibilityLabel("Set arm offset")
    }

    private func startArmCalibration() {
        guard let first = rawDistance() else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        armStage = 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            for remaining in stride(from: 4, through: 1, by: -1) {
                armCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            defer {
                armStage = 0
                armCountdown = 4
            }
            guard let second = rawDistance(), second > first + 0.05 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            armOffset = min(max(((second - first) * 100).rounded() / 100, 0), 0.8)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Engraved choice

/// Two or three engraved words with a sliding underline. Stands in for a segmented picker.
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = i }
                } label: {
                    Text(options[i])
                        .font(AppTypography.font(size: 12, weight: selection == i ? .semibold : .regular))
                        .foregroundStyle(selection == i ? Palette.ink : Palette.mutedInk)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            if selection == i {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "choiceUnderline", in: underlineNamespace)
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
    }
}

// MARK: - Mini stepper

private struct MiniStepper: View {
    let text: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", label: "Decrease", action: onMinus)
            Text(text)
                .font(AppTypography.font(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 56)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
