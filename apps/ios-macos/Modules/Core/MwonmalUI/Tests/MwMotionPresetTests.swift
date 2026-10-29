import Foundation
@testable import MwonmalUI
import SwiftUI
import Testing

/// ADR-0012 §6 불변식 + 끝 상태(ADR-0025). 중간 프레임은 보지 않는다(흔들리는 테스트가 된다).
struct MwTimingTests {
    @Test("시간표는 0.6초 이하, 스프링 response 0.8 이하", arguments: MwTiming.all + MwMotionTheme.default.timings)
    func bounds(_ timing: MwTiming) {
        #expect(timing.duration <= 0.6)
        #expect(timing.delay >= 0)
        if case let .spring(spring) = timing.curve {
            #expect(spring.response <= 0.8)
            #expect(spring.dampingFraction >= 0.8, "기본 시간표에는 튀는 스프링(pop·squash)을 쓰지 않는다")
        }
    }

    @Test("동작 줄이기: 스프링 없음, 지연 0, 0.15초 이하", arguments: MwTiming.all.map { $0.delayed(by: 0.3) })
    func reduced(_ timing: MwTiming) {
        let reduced = timing.reduced()
        if case .spring = reduced.curve {
            Issue.record("동작 줄이기에 스프링이 남았다: \(timing)")
        }
        #expect(reduced.delay == 0)
        #expect(reduced.duration <= MwTiming.reducedDuration)
    }

    @Test("길이 0은 애니메이션 없음") func instant() {
        #expect(MwTiming.instant.animation(reduceMotion: false) == nil)
        #expect(MwTiming.instant.animation(reduceMotion: true) == nil)
        #expect(MwTiming.paper.animation(reduceMotion: false) != nil)
    }

    @Test("Codable 왕복: 테마·곡선이 그대로 돌아온다") func codable() throws {
        var theme = MwMotionTheme.reduced
        theme.cardFlip = MwCardFlipSpec(timing: MwTiming(curve: .easeOut, duration: 0.2, delay: 0.05), perspective: 0.4, liftScale: 1.05)
        theme.sheetPresent.timing = MwTiming(spring: .snappy)
        let data = try JSONEncoder().encode(theme)
        #expect(try JSONDecoder().decode(MwMotionTheme.self, from: data) == theme)
        #expect(try JSONDecoder().decode(MwMotionTheme.self, from: JSONEncoder().encode(MwMotionTheme.default)) == .default)
    }
}

struct MwPresetMathTests {
    let flip = MwCardFlipSpec.default
    let pulse = MwDecodingPulseSpec.default

    @Test("카드 뒤집기: 0·0.5·1 → 0°·90°·180°, 끝에서 회전 0·크기 1") func cardFlip() {
        #expect(flip.angle(at: 0) == 0)
        #expect(flip.angle(at: 0.5) == 90)
        #expect(flip.angle(at: 1) == 180)
        #expect(!flip.showsBack(at: 0.49) && flip.showsBack(at: 0.5))
        #expect(flip.faceAngle(at: 0) == 0)
        #expect(flip.faceAngle(at: 1) == 0)
        #expect(flip.lift(at: 0) == 1 && flip.lift(at: 1) == 1)
        #expect(abs(flip.lift(at: 0.5) - flip.liftScale) < 1e-9)
        #expect(flip.angle(at: -1) == 0 && flip.angle(at: 2) == 180)
    }

    @Test("맥박: 시작은 원래 모습, 반 주기에 가장 옅고, 한 주기에 돌아온다") func decodingPulse() {
        #expect(pulse.opacity(at: 0) == 1 && pulse.scale(at: 0) == 1)
        #expect(abs(pulse.opacity(at: pulse.period / 2) - pulse.minOpacity) < 1e-9)
        #expect(abs(pulse.scale(at: pulse.period / 2) - pulse.peakScale) < 1e-9)
        #expect(abs(pulse.opacity(at: pulse.period) - 1) < 1e-9)
        #expect(pulse.opacity(at: -2) == 1)
        for step in 0 ... 28 {
            let value = pulse.opacity(at: Double(step) * 0.05)
            #expect(value >= pulse.minOpacity - 1e-9 && value <= 1)
        }
    }

    @Test("동작 줄이기 판단: 시스템 값 또는 주입한 .reduced") func reduceFlag() {
        var values = EnvironmentValues()
        #expect(values.mwReduceMotion == false)
        values.mwMotion = .reduced
        #expect(values.mwReduceMotion == true)
    }
}

/// 끝 상태 스냅샷(스냅샷 라이브러리는 S6 → `ImageRenderer`로 픽셀 비교).
@MainActor
struct MwPresetEndStateTests {
    static let size = CGSize(width: 120, height: 80)

    static func face(_ color: Color, _ label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(color)
            Text(verbatim: label).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size.width, height: size.height)
    }

    static func pixels(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
        return data as Data
    }

    @Test("비교가 의미 있다: 앞면과 뒷면 그림은 다르다") func facesDiffer() throws {
        let front = try #require(Self.pixels(Self.face(.blue, "앞")))
        #expect(front != Self.pixels(Self.face(.orange, "뒤")))
        #expect(front != Self.pixels(Self.face(.blue, "앞").opacity(0.9)))
    }

    @Test("카드 뒤집기 끝 상태 = 보이는 면 그대로", arguments: [MwMotionTheme.default, .reduced], [false, true])
    func cardFlipEnd(theme: MwMotionTheme, isFlipped: Bool) throws {
        let flipped = Self.face(.blue, "앞").mwCardFlip(isFlipped: isFlipped) { Self.face(.orange, "뒤") }.mwMotionTheme(theme)
        let expected = isFlipped ? Self.face(.orange, "뒤") : Self.face(.blue, "앞")
        let actual = try #require(Self.pixels(flipped))
        #expect(actual == Self.pixels(expected), "isFlipped=\(isFlipped) reduced=\(theme.isReduced)")
    }

    @Test("맥박이 꺼졌거나 동작 줄이기면 원래 모습", arguments: [(false, MwMotionTheme.default), (false, .reduced), (true, .reduced)])
    func pulseEnd(isActive: Bool, theme: MwMotionTheme) throws {
        let pulsing = Self.face(.teal, "해석").mwDecodingPulse(isActive: isActive).mwMotionTheme(theme)
        let actual = try #require(Self.pixels(pulsing))
        #expect(actual == Self.pixels(Self.face(.teal, "해석")))
    }
}
