import SwiftUI

@main
struct RolleiMeterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.font, AppTypography.regular(size: 17))
        }
    }
}
