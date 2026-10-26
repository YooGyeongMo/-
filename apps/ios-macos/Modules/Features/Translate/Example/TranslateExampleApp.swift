import DomainTesting
import SwiftUI
import TranslateFeature

/// 로그인·서버 없이 해석 흐름만 띄우는 예제 앱(ADR-0016). Fake는 DomainTesting에서 가져온다.
@main
struct TranslateExampleApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { TranslateRootView() }
        }
    }
}
