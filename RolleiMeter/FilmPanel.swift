import SwiftUI
import UIKit

// MARK: - Universal Camera & Film Top Bar Glass Pill

struct FilmPanel: View {
    @Binding var isoIndex: Int
    let useDIN: Bool
    let filmName: String
    let boxISO: Int
    var isUnloaded: Bool = false
    var cameraBadge: String = ""
    let onTap: () -> Void

    @State private var dragBase: Int?

    private var safeIndex: Int { min(max(isoIndex, 0), ISOScale.values.count - 1) }
    private var currentISO: Int { ISOScale.values[safeIndex] }

    private var speedText: String {
        let value = ISOScale.label(currentISO, din: useDIN)
        return useDIN ? value + "\u{00B0}" : "ISO " + value
    }

    private var resolvedCameraName: String {
        let trimmed = cameraBadge.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Camera" : trimmed
    }

    private var resolvedFilmLabel: String {
        if isUnloaded {
            return dragBase != nil ? speedText : "Load Film"
        }
        if useDIN {
            return "\(filmName) \u{00B7} \(ISOScale.label(currentISO, din: true))\u{00B0}"
        }
        if currentISO != boxISO {
            return "\(filmName) @ \(currentISO)"
        }
        return filmName
    }

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.84, blue: 0.04))
                    .frame(width: 7, height: 7)

                Text(resolvedCameraName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(resolvedFilmLabel)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.15), value: resolvedFilmLabel)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard let box = ISOScale.values.firstIndex(of: boxISO), isoIndex != box else { return }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                    isoIndex = box
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if dragBase == nil { dragBase = safeIndex }
                    let steps = Int((value.translation.width / 22).rounded())
                    let target = min(max((dragBase ?? safeIndex) + steps, 0), ISOScale.values.count - 1)
                    guard target != isoIndex else { return }
                    isoIndex = target
                    if ISOScale.values[target] == boxISO {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                    } else {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                .onEnded { _ in dragBase = nil }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera and Film")
        .accessibilityValue("\(resolvedCameraName), \(resolvedFilmLabel)")
        .accessibilityHint("Tap to choose camera or film, drag horizontally to rate ISO")
    }
}
