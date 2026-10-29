import Foundation

// 프리셋 스펙(ADR-0012 §4-1, v1.0 3개). 여러 속성 + 순서가 있는 움직임을 값으로 묶는다.
// 모두 `Codable`이라 카탈로그에서 바꾼 값을 그대로 옮길 수 있다. 진행률 → 값 함수는 순수 함수라 테스트한다.

/// 카드 뒤집기(복습 카드 앞 → 뒤, 05번 §3). y축으로 180° 돌며 가운데에서 살짝 들린다.
public nonisolated struct MwCardFlipSpec: Hashable, Codable, Sendable {
    public var timing: MwTiming
    /// 원근감(0 = 평면). 클수록 가까이서 보는 것처럼 휜다.
    public var perspective: Double
    /// 가운데(90°)에서 커지는 정도.
    public var liftScale: Double

    public init(timing: MwTiming = .paper, perspective: Double = 0.55, liftScale: Double = 1.03) {
        self.timing = timing
        self.perspective = perspective
        self.liftScale = liftScale
    }

    public static let `default` = MwCardFlipSpec()

    /// 진행률(0 = 앞, 1 = 뒤) → 돈 각도(도).
    public func angle(at progress: Double) -> Double {
        Self.clamp(progress) * 180
    }

    /// 지금 뒷면이 보이는지(절반을 넘으면).
    public func showsBack(at progress: Double) -> Bool {
        Self.clamp(progress) >= 0.5
    }

    /// 보이는 면이 실제로 도는 각도. 뒷면은 -90° → 0°로 돌아와 끝에서 변형이 없다(끝 상태 = 뒷면 그대로).
    public func faceAngle(at progress: Double) -> Double {
        let angle = angle(at: progress)
        return showsBack(at: progress) ? angle - 180 : angle
    }

    /// 들림 배율. 시작·끝에서 정확히 1.
    public func lift(at progress: Double) -> Double {
        let value = Self.clamp(progress)
        guard value > 0, value < 1 else { return 1 }
        return 1 + (liftScale - 1) * sin(value * .pi)
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// 해석 중 맥박(결과를 기다리는 자리). 천천히 옅어졌다 돌아온다. 동작 줄이기면 멈추고 진행 표시만 남는다.
public nonisolated struct MwDecodingPulseSpec: Hashable, Codable, Sendable {
    /// 한 번 숨 쉬는 시간(초).
    public var period: Double
    /// 가장 옅을 때의 투명도.
    public var minOpacity: Double
    /// 가장 부풀 때의 크기.
    public var peakScale: Double

    public init(period: Double = 1.4, minOpacity: Double = 0.45, peakScale: Double = 1.015) {
        self.period = period
        self.minOpacity = minOpacity
        self.peakScale = peakScale
    }

    public static let `default` = MwDecodingPulseSpec()

    /// 0(제자리) → 1(가장 옅음) → 0. 시작에서 속도 0이라 튀지 않는다.
    public func phase(at elapsed: Double) -> Double {
        guard elapsed > 0, period > 0 else { return 0 }
        return (1 - cos(2 * .pi * elapsed / period)) / 2
    }

    public func opacity(at elapsed: Double) -> Double {
        1 - (1 - minOpacity) * phase(at: elapsed)
    }

    public func scale(at elapsed: Double) -> Double {
        1 + (peakScale - 1) * phase(at: elapsed)
    }
}

/// 앱이 그리는 아래 오버레이(토스트·안내 띠)가 올라오고 내려갈 때. 시스템 `.sheet`는 타이밍을 못 바꾸므로 대상이 아니다.
public nonisolated struct MwSheetPresentSpec: Hashable, Codable, Sendable {
    public var timing: MwTiming
    /// 들어오기 전 아래로 떨어진 거리(pt).
    public var travel: Double
    /// 뒤를 어둡게 할 때의 투명도(어둡게 하는 오버레이에만).
    public var dimOpacity: Double

    public init(timing: MwTiming = .soft, travel: Double = 24, dimOpacity: Double = 0.28) {
        self.timing = timing
        self.travel = travel
        self.dimOpacity = dimOpacity
    }

    public static let `default` = MwSheetPresentSpec()
}

/// 프리셋 묶음(`@Entry mwMotion`). `.reduced`는 동작 줄이기 프로필(QA-3): 프리셋은 같고 `isReduced`만 켜진다.
public nonisolated struct MwMotionTheme: Hashable, Codable, Sendable {
    public var cardFlip: MwCardFlipSpec
    public var decodingPulse: MwDecodingPulseSpec
    public var sheetPresent: MwSheetPresentSpec
    public var isReduced: Bool

    public init(
        cardFlip: MwCardFlipSpec = .default,
        decodingPulse: MwDecodingPulseSpec = .default,
        sheetPresent: MwSheetPresentSpec = .default,
        isReduced: Bool = false
    ) {
        self.cardFlip = cardFlip
        self.decodingPulse = decodingPulse
        self.sheetPresent = sheetPresent
        self.isReduced = isReduced
    }

    public static let `default` = MwMotionTheme()
    public static let reduced = MwMotionTheme(isReduced: true)

    /// 묶음 안의 모든 시간표(불변식 테스트용).
    public var timings: [MwTiming] {
        [cardFlip.timing, sheetPresent.timing]
    }
}
