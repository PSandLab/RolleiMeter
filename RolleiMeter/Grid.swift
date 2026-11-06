import SwiftUI

// MARK: - 12 × 6 grid

struct LiquidGrid {
    static let landscapeSize = CGSize(width: 1460, height: 665)   // 12 x 6 cells
    static let portraitSize = CGSize(width: 706, height: 1498)    // 6 x 13 cells
    private static let colPitch: CGFloat = 126
    private static let rowPitch: CGFloat = 119

    let k: CGFloat
    let portrait: Bool
    /// Vertical shift that centres the grid between the top and bottom safe areas (portrait only).
    let yShift: CGFloat

    init(screen: CGSize, insets: EdgeInsets) {
        portrait = screen.height > screen.width
        if portrait {
            let usableHeight = max(screen.height - insets.top - insets.bottom, 1)
            k = max(0.2, min(screen.width / (Self.portraitSize.width + 80),
                             usableHeight / (Self.portraitSize.height + 24)))
            yShift = (insets.top - insets.bottom) / 2
        } else {
            let sideInset = max(insets.leading, insets.trailing)
            let usableWidth = max(screen.width - 2 * sideInset, 1)
            k = max(0.2, min(screen.height / 761, screen.width / 1646, usableWidth / 1460))
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
            width: (CGFloat(cols) * Self.colPitch - 36) * k,
            height: (CGFloat(rows) * Self.rowPitch - 36) * k
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
