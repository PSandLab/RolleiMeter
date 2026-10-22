import SwiftUI
import UIKit

struct ControlTray: View {
    @Binding var evIndex: Int
    @Binding var isoIndex: Int
    @Binding var useDIN: Bool
    @Binding var useFeet: Bool
    @Binding var calibration: Double
    @Binding var armOffset: Double
    let rawDistance: () -> Double?
    let onClose: () -> Void

    @State private var tab = 0
    @State private var armStage = 0
    @State private var armCountdown = 4
    @State private var armTask: Task<Void, Never>?
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 6) {
            header
            if tab == 0 {
                horizontalDials
            } else {
                options
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 174, maxHeight: 174)
        .modifier(Panel())
        .onDisappear {
            armTask?.cancel()
            armStage = 0
            armCountdown = 4
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 20) {
                tabButton("DIALS", 0)
                tabButton("OPTIONS", 1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.mutedInk)
                    .frame(width: 26, height: 26)
                    .background(Palette.well, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = index }
        } label: {
            Text(title)
                .font(AppTypography.next(size: 11, weight: tab == index ? .bold : .regular))
                .tracking(1.1)
                .foregroundStyle(tab == index ? Palette.ink : Palette.mutedInk)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    if tab == index {
                        Rectangle()
                            .fill(Palette.braunOrange)
                            .frame(height: 1.5)
                            .matchedGeometryEffect(id: "tabUnderline", in: tabNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var horizontalDials: some View {
        VStack(spacing: 6) {
            HorizontalScrubDial(
                title: "EV COMPENSATION",
                selection: $evIndex,
                labels: EVComp.labels,
                resetIndex: EVComp.zeroIndex
            )
            HorizontalScrubDial(
                title: useDIN ? "FILM SPEED (DIN)" : "FILM SPEED (ISO)",
                selection: $isoIndex,
                labels: ISOScale.values.map { ISOScale.label($0, din: useDIN) },
                resetIndex: ISOScale.values.firstIndex(of: 100)
            )
        }
    }

    private var options: some View {
        VStack(spacing: 0) {
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
        .frame(height: 28)
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
            Text(armStage == 0 ? "SET" : "HOLD AT EYE · \(armCountdown)")
                .font(AppTypography.next(size: 11, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.18), value: armCountdown)
                .animation(.smooth(duration: 0.18), value: armStage)
                .tracking(0.8)
                .foregroundStyle(armStage == 0 ? Palette.ink : Palette.braunOrange)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Palette.ink.opacity(0.08), in: Capsule())
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = i }
                } label: {
                    Text(options[i])
                        .font(AppTypography.font(size: 11, weight: selection == i ? .bold : .regular))
                        .foregroundStyle(selection == i ? Palette.ink : Palette.mutedInk)
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) {
                            if selection == i {
                                Rectangle()
                                    .fill(Palette.braunOrange)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "choiceUnderline", in: underlineNamespace)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 26)
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
                .foregroundStyle(Palette.ink)
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
                .foregroundStyle(Palette.ink)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
