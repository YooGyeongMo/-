import Composition
import SwiftUI

/// macOS 앱. 화면은 iPhone과 같은 Composition을 쓰고, 넓은 화면 분기(사이드바 + 상세)는 루트가 고른다(ADR-0006).
/// 창: 최소 1000×700, 기본 1280×800(12번 D-20). 메뉴: ⌘N 새 해석, ⌘1~4 화면 이동.
@main
struct MwonmalMacApp: App {
    var body: some Scene {
        WindowGroup {
            SessionRootView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands { MwonmalCommands() }
    }
}
