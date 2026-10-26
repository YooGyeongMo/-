import Composition
import SwiftUI

@main
struct MwonmalMacApp: App {
    var body: some Scene {
        WindowGroup { SessionRootView() }
            .defaultSize(width: 1200, height: 800)
    }
}
