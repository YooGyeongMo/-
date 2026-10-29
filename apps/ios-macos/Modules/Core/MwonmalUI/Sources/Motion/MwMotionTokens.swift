import SwiftUI

/// 곡선 종류(ADR-0012 §4-1). 스프링은 `MwSpring` 값을 그대로 품는다.
public nonisolated enum MwCurve: Hashable, Codable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case spring(MwSpring)
}

/// 움직임 하나의 시간표: 곡선 + 길이 + 지연(ADR-0012). 화면은 숫자 대신 이 이름만 쓴다.
///
/// 스프링이면 길이는 스프링의 `response`다(끝나는 시점의 기준).
/// 동작 줄이기면 곡선은 easeInOut, 길이는 0.15초 이하, 지연은 0이 된다(`reduced()`).
public nonisolated struct MwTiming: Hashable, Codable, Sendable {
    public var curve: MwCurve
    public var duration: Double
    public var delay: Double

    public init(curve: MwCurve, duration: Double, delay: Double = 0) {
        self.curve = curve
        self.duration = duration
        self.delay = delay
    }

    public init(spring: MwSpring, delay: Double = 0) {
        self.init(curve: .spring(spring), duration: spring.response, delay: delay)
    }

    /// 움직이지 않는다(바로 바뀜).
    public static let instant = MwTiming(curve: .linear, duration: 0)
    /// 작은 색·투명도 변화.
    public static let quick = MwTiming(curve: .easeOut, duration: 0.16)
    /// 보통 크기 변화, 동작 줄이기 대신 곡선의 기준.
    public static let standard = MwTiming(curve: .easeInOut, duration: 0.24)
    public static let paper = MwTiming(spring: .paper)
    public static let snappy = MwTiming(spring: .snappy)
    public static let soft = MwTiming(spring: .soft)

    /// 테스트·카탈로그가 전부를 훑을 수 있게.
    public static let all: [MwTiming] = [.instant, .quick, .standard, .paper, .snappy, .soft]

    /// 동작 줄이기에서 허용하는 가장 긴 길이.
    public static let reducedDuration: Double = 0.15

    public func delayed(by extra: Double) -> MwTiming {
        MwTiming(curve: curve, duration: duration, delay: delay + extra)
    }

    /// 동작 줄이기로 바꾼 시간표: 스프링 없음, 지연 0, 0.15초 이하 페이드.
    public func reduced() -> MwTiming {
        duration == 0 ? .instant : MwTiming(curve: .easeInOut, duration: min(duration, Self.reducedDuration))
    }

    /// SwiftUI `Animation`. 길이 0이면 nil(애니메이션 없이 바로).
    public func animation(reduceMotion: Bool) -> Animation? {
        let timing = reduceMotion ? reduced() : self
        guard timing.duration > 0 else { return nil }
        let base: Animation = switch timing.curve {
        case .linear: .linear(duration: timing.duration)
        case .easeIn: .easeIn(duration: timing.duration)
        case .easeOut: .easeOut(duration: timing.duration)
        case .easeInOut: .easeInOut(duration: timing.duration)
        case let .spring(spring): spring.animation
        }
        return timing.delay > 0 ? base.delay(timing.delay) : base
    }
}

public extension EnvironmentValues {
    /// 움직임 묶음(ADR-0012 `@Entry mwMotion`). 테스트·카탈로그는 `.reduced`를 넣어 동작 줄이기를 흉내 낸다.
    @Entry var mwMotion: MwMotionTheme = .default

    /// 움직임을 줄여야 하는지: 시스템 "동작 줄이기" 또는 주입한 `.reduced` 테마.
    /// 시스템 값(`accessibilityReduceMotion`)은 읽기 전용이라 테스트가 바꿀 수 없다 → 둘을 함께 본다(ADR-0012 §3).
    var mwReduceMotion: Bool {
        accessibilityReduceMotion || mwMotion.isReduced
    }
}

public extension View {
    /// 아래 뷰들의 움직임 묶음을 바꾼다(카탈로그·테스트, 또는 화면 하나만 다르게).
    func mwMotionTheme(_ theme: MwMotionTheme) -> some View {
        environment(\.mwMotion, theme)
    }
}
