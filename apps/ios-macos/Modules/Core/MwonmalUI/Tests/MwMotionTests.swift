import CoreGraphics
@testable import MwonmalUI
import Testing

/// ADR-0012·0024 움직임 불변식.
struct MwMotionTests {
    @Test("일반 스프링은 감쇠 0.8 이상, 예외는 pop·squash 둘뿐") func damping() {
        let bouncy = MwSpring.all.filter { $0.dampingFraction < 0.8 }
        #expect(Set(bouncy) == [MwSpring.pop, MwSpring.squash])
        #expect(MwSpring.all.allSatisfy { $0.response <= 0.8 && $0.dampingFraction >= 0.6 })
    }

    @Test("스태거: 0부터 단조 증가, 상한에서 멈춘다", arguments: [MwStagger.text, MwStagger.chips])
    func stagger(_ stagger: MwStagger) {
        let delays = (0 ... 40).map(stagger.delay(for:))
        #expect(delays.first == 0)
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(delays.last == stagger.cap)
        #expect(stagger.delay(for: -3) == 0)
    }

    @Test("떠다니기는 0에서 시작해 한 주기 뒤 0으로, 위로만 간다") func float() {
        let period = 3.2
        #expect(MwFloat.offset(elapsed: 0, amplitude: 4, period: period) == 0)
        #expect(abs(MwFloat.offset(elapsed: period, amplitude: 4, period: period)) < 0.0001)
        #expect(abs(MwFloat.offset(elapsed: period / 2, amplitude: 4, period: period) + 4) < 0.0001)
        #expect(MwFloat.offset(elapsed: -1, amplitude: 4, period: period) == 0)
        for step in 0 ... 32 {
            let value = MwFloat.offset(elapsed: Double(step) * 0.1, amplitude: 4, period: period)
            #expect(value <= 0 && value >= -4)
        }
    }

    @Test("다이브: 제자리 1, 멀리 작게, 지나치면 크게") func dive() {
        #expect(MwDive.scale(for: 0) == 1)
        #expect(MwDive.scale(for: -1) < 1)
        #expect(MwDive.scale(for: 1) > 1)
    }

    @Test("반딧불: 번호가 같으면 같은 자리, 개수는 12개까지") func fireflies() {
        let size = CGSize(width: 393, height: 300)
        #expect(Firefly(index: 3).position(at: 10, in: size) == Firefly(index: 3).position(at: 10, in: size))
        #expect(Firefly(index: 3).position(at: 10, in: size) != Firefly(index: 4).position(at: 10, in: size))
        for index in 0 ..< MwFireflies.maxCount {
            let glow = Firefly(index: index).glow(at: Double(index) * 1.7)
            #expect(glow >= 0.25 - 0.0001 && glow <= 1.0001)
        }
        #expect(MwFireflies(count: 40).count == MwFireflies.maxCount)
    }
}

/// 온보딩 그림 무대(Figma 393×500). 화면 비율이 달라도 무대는 가운데·바닥에 붙는다.
struct OnboardingStageTests {
    @Test("Figma 크기에서는 배율 1, 원점 0") func figma() {
        let size = CGSize(width: 393, height: 500)
        #expect(OnboardingStage.scale(for: size) == 1)
        #expect(OnboardingStage.origin(for: size, scale: 1) == .zero)
    }

    @Test("낮은 화면: 높이에 맞추고 가운데·바닥") func short() {
        let size = CGSize(width: 375, height: 300)
        let scale = OnboardingStage.scale(for: size)
        #expect(scale == CGFloat(300) / 500)
        let origin = OnboardingStage.origin(for: size, scale: scale)
        #expect(origin.y == 0)
        #expect(abs(origin.x - (375 - 393 * scale) / 2) < 0.0001)
    }

    @Test("넓은 패널: 상한 1.6에서 멈추고 바닥에 붙는다") func wide() {
        let size = CGSize(width: 1200, height: 1000)
        let scale = OnboardingStage.scale(for: size)
        #expect(scale == 1.6)
        #expect(OnboardingStage.origin(for: size, scale: scale).y == 1000 - 500 * 1.6)
    }

    @Test("쪽 3개, 칩 기준점은 무대 안") func pages() {
        #expect(OnboardingStage.pages.count == OnboardingStage.pageCount)
        for page in OnboardingStage.pages {
            for layer in page.layers {
                if case let .pop(anchor, _, _, _) = layer.kind {
                    #expect((0 ... 1).contains(anchor.x) && (0 ... 1).contains(anchor.y), "\(layer.name)")
                }
            }
        }
    }
}
