import SwiftUI

/// 시맨틱 색 토큰(ADR-0017). 화면은 이 이름만 쓴다. 값은 `Colors.xcassets`에 라이트·다크·고대비 4벌로 있어
/// 코드에서 외관·대비를 분기하지 않는다. 팔레트(ocean·sun…)는 노출하지 않는다.
public enum MwColor {
    public static let canvas = token("bg.canvas")
    public static let surface = token("bg.surface")
    public static let surfaceMuted = token("bg.surfaceMuted")
    /// 브랜드 패널(S-01 하단 하늘색). 일러스트와 이어지는 면에만 쓴다.
    public static let brandPanel = token("bg.brandPanel")

    public static let textPrimary = token("text.primary")
    public static let textSecondary = token("text.secondary")
    /// canvas·surface 위에서만(muted 위에서는 secondary).
    public static let textTertiary = token("text.tertiary")

    public static let accentFill = token("accent.fill")
    public static let accentOnFill = token("accent.onFill")
    public static let accentText = token("accent.text")

    public static let separator = token("separator")
    public static let controlBorder = token("control.border")

    public static let jargonFill = token("jargon.fill")
    public static let jargonUnderline = token("jargon.underline")
    public static let jargonChipFill = token("jargon.chipFill")
    public static let jargonChipText = token("jargon.chipText")

    public static let urgentFill = token("status.urgentFill")
    public static let urgentText = token("status.urgentText")
    public static let soonFill = token("status.soonFill")
    public static let soonText = token("status.soonText")
    public static let doneFill = token("status.doneFill")
    public static let doneText = token("status.doneText")

    /// 테스트·카탈로그가 전부를 훑을 수 있게.
    public static let allNames: [String] = [
        "bg.canvas", "bg.surface", "bg.surfaceMuted", "bg.brandPanel",
        "text.primary", "text.secondary", "text.tertiary",
        "accent.fill", "accent.onFill", "accent.text", "separator", "control.border",
        "jargon.fill", "jargon.underline", "jargon.chipFill", "jargon.chipText",
        "status.urgentFill", "status.urgentText", "status.soonFill", "status.soonText",
        "status.doneFill", "status.doneText",
    ]

    static func token(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}
