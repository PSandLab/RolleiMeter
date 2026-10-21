import SwiftUI

@main
struct RolleiMeterApp: App {
    init() {
        AppTypography.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.font, AppTypography.regular(size: 17))
        }
    }
}
