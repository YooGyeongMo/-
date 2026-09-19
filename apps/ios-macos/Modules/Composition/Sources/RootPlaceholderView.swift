import SwiftUI

/// S0 Day 5에서 TabCoordinator 기반 AppRootView로 교체된다.
public struct RootPlaceholderView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 12) {
            Text("뭔말인교?").font(.largeTitle.bold())
            Text("S0 뼈대").foregroundStyle(.secondary)
        }
        .padding()
    }
}
