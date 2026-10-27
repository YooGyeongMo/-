import SwiftUI

/// Figma 기준 프레임(iPhone 16·17 Pro 393×852pt). 화면의 모든 pt는 Figma 값 × 배율이다.
public enum MwFrame {
    public static let width: CGFloat = 393
    public static let height: CGFloat = 852

    /// 기기 배율. 너비 기준(현재 iPhone 라인업은 화면 비율이 2.16~2.17로 Figma와 같다).
    /// iPad·Mac(v1.3·v1.4)에서 지나치게 커지지 않게 1.25에서 멈춘다.
    public static func scale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(width / Self.width, 1.25)
    }
}

public extension EnvironmentValues {
    /// Figma → 기기 배율(너비/393). 루트에서 한 번 넣고 모든 화면이 읽는다.
    @Entry var mwScale: CGFloat = 1
}

public extension View {
    /// 루트에 붙인다: 너비를 재서 `mwScale`을 넣는다.
    func mwScaledToWidth() -> some View {
        modifier(MwScaleRoot())
    }
}

private struct MwScaleRoot: ViewModifier {
    @State private var width: CGFloat = MwFrame.width

    func body(content: Content) -> some View {
        content
            .environment(\.mwScale, MwFrame.scale(forWidth: width))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Figma 글자 스타일: Pretendard 굵기·크기·줄 높이·자간 × 배율 × 글자 크기 설정.
///
/// CSS 줄 높이(line-height)는 글꼴 기본 줄 높이(Pretendard ≈ 1.193em)보다 크면 위아래로 반씩 여백을 준다.
/// 그래서 여러 줄은 `lineSpacing`, 한 줄의 위아래는 `padding`으로 같은 상자를 만든다.
public struct MwTextStyle: ViewModifier {
    let weight: MwFont.Weight
    let size: CGFloat
    let lineHeight: CGFloat?
    let tracking: CGFloat

    @Environment(\.mwScale) private var scale
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    public static let naturalLineHeight: CGFloat = 1.193

    public func body(content: Content) -> some View {
        let k = scale * typeScale
        let leading = max((lineHeight ?? size * Self.naturalLineHeight) - size * Self.naturalLineHeight, 0)
        content
            .font(MwFont.pretendard(weight, size: size * k))
            .tracking(tracking * k)
            .lineSpacing(leading * k)
            .padding(.vertical, leading * k / 2)
    }
}

public extension View {
    /// Figma 글자 스타일. 크기·줄 높이·자간은 Figma pt 그대로 쓴다(배율은 알아서 곱한다).
    func mwFont(_ weight: MwFont.Weight, _ size: CGFloat, lineHeight: CGFloat? = nil, tracking: CGFloat = 0) -> some View {
        modifier(MwTextStyle(weight: weight, size: size, lineHeight: lineHeight, tracking: tracking))
    }
}

/// 배율을 곱한 길이를 쓰기 위한 작은 도우미. `@Environment(\.mwScale)`를 읽는 뷰에서 쓴다.
public extension CGFloat {
    func s(_ scale: CGFloat) -> CGFloat {
        self * scale
    }
}

public extension Date {
    /// Figma 시각 표기 "17:30"(24시간제). 한국어 로캘의 기본 시각 형식은 12시간제라 따로 둔다.
    var mwClock: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
