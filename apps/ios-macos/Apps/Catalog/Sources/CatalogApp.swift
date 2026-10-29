import MwonmalUI
import SwiftUI

@main
struct CatalogApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("MotionLab") { MotionLab() }
                }
                .navigationTitle("MwonmalUI Catalog")
            }
        }
    }
}
