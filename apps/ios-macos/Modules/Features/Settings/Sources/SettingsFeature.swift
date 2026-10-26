import FeatureKit
import Routing
import SwiftUI

/// SettingsFeature 모듈(ADR-0016). 다른 Feature를 모르고, 이동은 `AppNavigating`으로만 요청한다.
public enum SettingsFeatureModule {
    public static let name = "SettingsFeature"
}

/// 자리표시 화면. 실제 화면은 해당 Day 이슈에서 교체한다.
public struct SettingsRootView: View {
    public init() {}

    public var body: some View {
        Text("settings.root.placeholder", bundle: .module)
    }
}
