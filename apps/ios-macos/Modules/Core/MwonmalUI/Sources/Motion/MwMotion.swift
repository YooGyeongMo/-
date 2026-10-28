import SwiftUI

/// 스프링 값 토큰(ADR-0012). 화면은 숫자 대신 이 이름만 쓴다.
public struct MwSpring: Hashable, Sendable {
    public let response: Double
    public let dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }

    /// 종이가 내려앉는 기본 움직임.
    public static let paper = MwSpring(response: 0.38, dampingFraction: 0.86)
    /// 짧고 단단한 반응(버튼·토글).
    public static let snappy = MwSpring(response: 0.26, dampingFraction: 0.92)
    /// 크게 움직이는 면(장면 전환·초점 맞추기).
    public static let soft = MwSpring(response: 0.55, dampingFraction: 0.95)
    /// 튀어나오는 칩·말풍선. 살짝 넘쳤다 돌아온다(ADR-0024).
    public static let pop = MwSpring(response: 0.42, dampingFraction: 0.7)
    /// 시작 화면이 아이콘으로 접힐 때 한 번만 쓰는 찌그러짐(ADR-0024). 다른 곳에는 쓰지 않는다.
    public static let squash = MwSpring(response: 0.5, dampingFraction: 0.62)

    /// 테스트·카탈로그가 전부를 훑을 수 있게.
    public static let all: [MwSpring] = [.paper, .snappy, .soft, .pop, .squash]

    var animation: Animation {
        .spring(response: response, dampingFraction: dampingFraction)
    }
}

/// 차례로 나타나는 요소의 간격(ADR-0012 `MwStagger`). 너무 길어지지 않게 상한이 있다.
public struct MwStagger: Hashable, Sendable {
    public let interval: Double
    public let cap: Double

    public init(interval: Double, cap: Double) {
        self.interval = interval
        self.cap = cap
    }

    /// 글자 줄이 하나씩 올라올 때.
    public static let text = MwStagger(interval: 0.08, cap: 0.6)
    /// 그림 속 칩이 튀어나올 때.
    public static let chips = MwStagger(interval: 0.09, cap: 0.9)

    public func delay(for index: Int) -> Double {
        min(Double(max(index, 0)) * interval, cap)
    }
}

/// 애니메이션 프리셋(ADR-0012·0024). 화면은 곡선 리터럴 대신 이것만 쓴다. 동작 줄이기 설정이면
/// 스프링·지연 없이 짧은 페이드(0.15초)로 바뀌고, 계속 도는 움직임은 멈춘다.
public enum MwMotion {
    /// 동작 줄이기에서 쓰는 대신 곡선.
    static let reduced = Animation.easeInOut(duration: 0.15)

    /// 아래 안내(토스트)가 나타나고 사라질 때.
    public static func toast(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }

    /// 스프링 토큰 → Animation. 지연은 차례 연출에만 쓴다.
    public static func spring(_ spring: MwSpring, delay: Double = 0, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : spring.animation.delay(delay)
    }

    /// 화면(페이지) 전환. 들어오는 장면은 멀리서 다가오고, 나가는 장면은 카메라를 지나쳐 흐려진다(ADR-0024 다이브).
    public static func page(reduceMotion: Bool) -> Animation {
        spring(.soft, reduceMotion: reduceMotion)
    }

    /// 계속 떠다니는 움직임(칩 흔들림·자전거). 반 주기마다 방향이 바뀐다.
    static func float(period: Double) -> Animation {
        .easeInOut(duration: period / 2).repeatForever(autoreverses: true)
    }

    /// 버튼 둘레 물결 한 번이 퍼지는 시간.
    static let pulsePeriod: Double = 2.4
    /// 반딧불 화면 갱신 간격(초당 30번). 배터리를 위해 60이 아니다.
    static let ambientFrameInterval: Double = 1.0 / 30.0
}
