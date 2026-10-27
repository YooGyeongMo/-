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

    /// Figma v5.2 화면(A-01·A-06·A-09·A-11)에서 더 쓰는 값.
    public static let textStrong = token("text.strong") // #3A3150 칩 글자·날짜
    public static let textDisabled = token("text.disabled") // #A6A0AE 잠긴 등급·끝난 할 일·꺼진 탭
    public static let chipFill = token("chip.fill") // #EAE6F0
    public static let checkboxBorder = token("control.checkbox") // #D8D2C8
    public static let badgeFill = token("badge.fill") // #EE7A3B 탭 숫자 배지
    public static let accentShadow = token("accent.shadow") // #2459B4 파란 버튼 아래 2pt
    public static let accentSoftFill = token("accent.softFill") // #E4F2FA "지금" 배지
    public static let glassFill = token("glass.fill") // 흰 74%
    public static let glassFillThin = token("glass.fillThin") // 흰 60%
    public static let glassBorder = token("glass.border") // 흰 75%
    public static let tabSelected = token("tab.selected") // 흰 85%
    public static let jargonHighlight = token("jargon.highlight") // #F7C948 50% 형광펜
    public static let sheetGrabber = token("sheet.grabber")
    /// 홈 히어로(노란 하늘) 위 글자. 그림이 다크에서도 밝아 외관과 상관없이 어두운 색(QA H5).
    public static let onHeroPrimary = token("onHero.primary")
    public static let onHeroStrong = token("onHero.strong")

    /// 테스트·카탈로그가 전부를 훑을 수 있게.
    public static let allNames: [String] = [
        "bg.canvas", "bg.surface", "bg.surfaceMuted", "bg.brandPanel",
        "text.primary", "text.secondary", "text.tertiary",
        "accent.fill", "accent.onFill", "accent.text", "separator", "control.border",
        "jargon.fill", "jargon.underline", "jargon.chipFill", "jargon.chipText",
        "status.urgentFill", "status.urgentText", "status.soonFill", "status.soonText",
        "status.doneFill", "status.doneText",
        "text.strong", "text.disabled", "chip.fill", "control.checkbox", "badge.fill", "accent.shadow",
        "accent.softFill", "glass.fill", "glass.fillThin", "glass.border", "tab.selected", "jargon.highlight",
        "sheet.grabber", "onHero.primary", "onHero.strong",
    ]

    static func token(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}
