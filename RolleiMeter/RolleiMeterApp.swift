import SwiftUI

@main
struct RolleiMeterApp: App {
    init() {
        AppTypography.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environment(\.font, AppTypography.regular(size: 17))
        }
    }
}
