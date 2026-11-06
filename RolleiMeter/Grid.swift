import SwiftUI

// MARK: - 12 × 6 grid

struct LiquidGrid {
    private static let colPitch: CGFloat = 126
    private static let rowPitch: CGFloat = 119
    private static let gapX: CGFloat = 22
    private static let gapY: CGFloat = 22

    static let landscapeSize = CGSize(
        width: 12 * colPitch - gapX,
        height: 6 * rowPitch - gapY
    )
    static let portraitSize = CGSize(
        width: 6 * colPitch - gapX,
        height: 13 * rowPitch - gapY
    )

    let k: CGFloat
    let portrait: Bool
    /// Vertical shift that centres the grid between the top and bottom safe areas (portrait only).
    let yShift: CGFloat

    init(screen: CGSize, insets: EdgeInsets) {
        portrait = screen.height > screen.width
        if portrait {
            let usableHeight = max(screen.height - insets.top - insets.bottom, 1)
            k = max(0.2, min(screen.width / (Self.portraitSize.width + 64),
                             usableHeight / (Self.portraitSize.height + 20)))
            yShift = (insets.top - insets.bottom) / 2
        } else {
            let sideInset = max(insets.leading, insets.trailing)
            let usableWidth = max(screen.width - 2 * sideInset, 1)
            k = max(0.2, min(screen.height / (Self.landscapeSize.height + 64),
                             screen.width / (Self.landscapeSize.width + 120),
                             usableWidth / Self.landscapeSize.width))
            yShift = 0
        }
    }

    var size: CGSize {
        let d = portrait ? Self.portraitSize : Self.landscapeSize
        return CGSize(width: d.width * k, height: d.height * k)
    }

    func rect(col: Int, row: Int, cols: Int, rows: Int) -> CGRect {
        CGRect(
            x: CGFloat(col) * Self.colPitch * k,
            y: CGFloat(row) * Self.rowPitch * k,
            width: (CGFloat(cols) * Self.colPitch - Self.gapX) * k,
            height: (CGFloat(rows) * Self.rowPitch - Self.gapY) * k
        )
    }
}

extension View {
    func cell(_ grid: LiquidGrid, col: Int, row: Int, cols: Int, rows: Int) -> some View {
        let r = grid.rect(col: col, row: row, cols: cols, rows: rows)
        return self
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }
}
