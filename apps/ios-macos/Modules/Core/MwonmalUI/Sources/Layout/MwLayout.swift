import SwiftUI

/// 화면 폭 분류(ADR-0006). 사이즈 클래스 두 개가 모두 regular면 wide(Mac 항상, iPad 전체화면·넓은 Split),
/// 아니면 compact(iPhone 어느 방향이든, iPad Slide Over·1/3). 창 폭 숫자로 다시 계산하지 않는다.
public enum MwLayout: Sendable, Equatable {
    case compact
    case wide

    #if !os(macOS)
        /// 사이즈 클래스 → 분류(순수 함수, 4조합 테스트). macOS는 사이즈 클래스 환경값이 없어 항상 wide.
        public static func from(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> MwLayout {
            horizontal == .regular && vertical == .regular ? .wide : .compact
        }
    #endif

    /// 넓은 화면에서 본문 읽기 폭 상한(ADR-0006).
    public static let readableWidth: CGFloat = 680
    /// 넓은 화면 오른쪽 보조 열 폭(웹 W-01·W-03 시안의 오른쪽 열).
    public static let asideWidth: CGFloat = 320
}

public extension EnvironmentValues {
    /// 루트(AdaptiveRoot)가 넣는다. 화면은 이 값만 보고 자기 안의 배치를 바꾼다.
    @Entry var mwLayout: MwLayout = .compact
}

public extension View {
    /// 넓은 화면에서 가운데 정렬 + 읽기 폭 상한. 좁은 화면에서는 아무것도 하지 않는다.
    func mwReadableWidth(_ maxWidth: CGFloat = MwLayout.readableWidth) -> some View {
        modifier(MwReadableWidth(maxWidth: maxWidth))
    }
}

private struct MwReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.mwLayout) private var layout

    func body(content: Content) -> some View {
        if layout == .wide {
            content.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}
