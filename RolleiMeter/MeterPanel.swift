import SwiftUI
import UIKit

// MARK: - Metering mode

struct MeterPanel: View {
    let modes: [MeterMode]
    let index: Int
    let k: CGFloat
    let onPick: (Int) -> Void
    /// One quiet line of words with no title or captions (used inside the Hold panel).
    var compact: Bool = false

    private func caption(_ mode: MeterMode) -> String {
        switch mode {
        case .matrix: return "scene"
        case .highlight: return "peaks"
        case .spot: return "point"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(modes.indices, id: \.self) { i in
                    Button {
                        guard i != index else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onPick(i)
                    } label: {
                        VStack(spacing: 6 * k) {
                            Text(modes[i].title)
                                .font(AppTypography.next(size: (compact ? 30 : 31) * k, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if !compact {
                                Text(caption(modes[i]))
                                    .font(AppTypography.next(size: 23 * k))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(i == index ? Palette.accent : (compact ? Palette.dim : Palette.text))
                        .animation(.easeOut(duration: 0.18), value: index)
                        .frame(maxWidth: .infinity)
                        .padding(.top, compact ? 0 : 72 * k)
                        .frame(maxHeight: .infinity, alignment: compact ? .center : .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(modes[i].title + " metering")
                    .accessibilityAddTraits(i == index ? .isSelected : [])
                }
            }
            if !compact {
                PanelTitle(text: "METER", k: k)
                    .allowsHitTesting(false)
            }
        }
    }
}
