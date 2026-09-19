import SwiftUI
import MwonmalUI

@main
struct CatalogApp: App {
    var body: some Scene {
        WindowGroup { Text("MwonmalUI Catalog — \(MwonmalUIModule.name)").padding() }
    }
}
