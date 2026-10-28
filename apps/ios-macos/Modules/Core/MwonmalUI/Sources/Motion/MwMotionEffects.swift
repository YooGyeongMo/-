import SwiftUI

// 화면이 부르는 움직임 모디파이어(ADR-0024). 모두 "끝 상태 = Figma 그대로"다:
// 들어온 뒤에는 위치·크기·투명도가 원래 값으로 돌아오고, 계속 도는 움직임도 0에서 시작해 0으로 돌아온다.
// 동작 줄이기면 흐림·크기·이동 없이 짧은 페이드만 남고, 계속 도는 움직임은 멈춘다.

public extension View {
    /// 초점이 맞으며 나타난다(레퍼런스 영상의 rack focus): 흐림 14 → 0, 크기 1.04 → 1, 투명 → 불투명.
    func mwFocusIn(_ isIn: Bool, delay: Double = 0) -> some View {
        modifier(MwFocusIn(isIn: isIn, delay: delay))
    }

    /// 아래에서 떠오른다(제목 줄·본문이 차례로). `index`로 순서를 준다.
    func mwRise(_ isIn: Bool, index: Int = 0, stagger: MwStagger = .text, baseDelay: Double = 0) -> some View {
        modifier(MwRise(isIn: isIn, delay: baseDelay + stagger.delay(for: index)))
    }

    /// 화면 밖 `from`만큼 떨어진 곳에서 미끄러져 들어온다(자전거·알림 카드).
    func mwSlideIn(_ isIn: Bool, from offset: CGSize, delay: Double = 0) -> some View {
        modifier(MwSlideIn(isIn: isIn, from: offset, delay: delay))
    }

    /// 튀어나온다(칩·말풍선): 크기 0.4 → 1(살짝 넘쳤다 돌아옴), 기울기 → 0.
    func mwPop(_ isIn: Bool, index: Int = 0, tilt: Double = -8, baseDelay: Double = 0, anchor: UnitPoint = .center) -> some View {
        modifier(MwPop(isIn: isIn, delay: baseDelay + MwStagger.chips.delay(for: index), tilt: tilt, anchor: anchor))
    }

    /// 제자리에서 천천히 오르내린다. 0에서 시작해 위로 `amplitude`까지 갔다 돌아온다.
    func mwFloat(_ isActive: Bool, amplitude: CGFloat = 4, period: Double = 3.2, phase: Double = 0) -> some View {
        modifier(MwFloat(isActive: isActive, amplitude: amplitude, period: period, phase: phase))
    }

    /// 버튼 둘레로 옅은 물결이 퍼진다(마지막 행동 버튼에만).
    func mwPulseRing(_ isActive: Bool, cornerRadius: CGFloat, color: Color) -> some View {
        modifier(MwPulseRing(isActive: isActive, cornerRadius: cornerRadius, color: color))
    }
}

public extension AnyTransition {
    /// 장면 전환 "다이브"(레퍼런스 V1의 카메라 돌진): 나가는 장면은 커지며 흐려지고, 들어오는 장면은 멀리서 다가온다.
    /// `forward == false`(뒤로)면 방향이 반대다. 동작 줄이기면 페이드만.
    static func mwDive(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: MwDive(progress: forward ? -1 : 1), identity: MwDive(progress: 0)),
            removal: .modifier(active: MwDive(progress: forward ? 1 : -1), identity: MwDive(progress: 0))
        )
    }
}

/// -1 = 멀리(작고 흐림), 0 = 제자리, 1 = 카메라를 지나침(크고 흐림).
struct MwDive: ViewModifier {
    let progress: CGFloat

    static func scale(for progress: CGFloat) -> CGFloat {
        progress < 0 ? 1 + progress * 0.08 : 1 + progress * 0.14
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(Self.scale(for: progress))
            .blur(radius: abs(progress) * 12)
            .opacity(1 - Double(abs(progress)))
    }
}

struct MwFocusIn: ViewModifier {
    let isIn: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = isIn || reduceMotion
        content
            .blur(radius: still ? 0 : 14)
            .scaleEffect(still ? 1 : 1.04)
            .opacity(isIn ? 1 : 0)
            .animation(MwMotion.spring(.soft, delay: delay, reduceMotion: reduceMotion), value: isIn)
    }
}

struct MwRise: ViewModifier {
    let isIn: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mwScale) private var scale

    func body(content: Content) -> some View {
        let still = isIn || reduceMotion
        content
            .offset(y: still ? 0 : 18 * scale)
            .blur(radius: still ? 0 : 6)
            .opacity(isIn ? 1 : 0)
            .animation(MwMotion.spring(.paper, delay: delay, reduceMotion: reduceMotion), value: isIn)
    }
}

struct MwSlideIn: ViewModifier {
    let isIn: Bool
    let from: CGSize
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = isIn || reduceMotion
        content
            .offset(still ? .zero : from)
            .opacity(isIn ? 1 : 0)
            .animation(MwMotion.spring(.soft, delay: delay, reduceMotion: reduceMotion), value: isIn)
    }
}

struct MwPop: ViewModifier {
    let isIn: Bool
    let delay: Double
    let tilt: Double
    let anchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = isIn || reduceMotion
        content
            .scaleEffect(still ? 1 : 0.4, anchor: anchor)
            .rotationEffect(.degrees(still ? 0 : tilt), anchor: anchor)
            .opacity(isIn ? 1 : 0)
            .animation(MwMotion.spring(.pop, delay: delay, reduceMotion: reduceMotion), value: isIn)
    }
}

/// 시간 함수로 위치를 구한다(반복 애니메이션은 멈출 때 끝 값이 꼬인다). 꺼지면 0.
struct MwFloat: ViewModifier {
    let isActive: Bool
    let amplitude: CGFloat
    let period: Double
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// 0(제자리) → -amplitude(위) → 0. 시작과 끝에서 속도가 0이라 튀지 않는다.
    static func offset(elapsed: Double, amplitude: CGFloat, period: Double) -> CGFloat {
        guard elapsed > 0, period > 0 else { return 0 }
        return -amplitude * CGFloat(1 - cos(2 * .pi * elapsed / period)) / 2
    }

    func body(content: Content) -> some View {
        let running = isActive && !reduceMotion
        TimelineView(.animation(paused: !running)) { context in
            content.offset(y: running ? Self.offset(
                elapsed: context.date.timeIntervalSince(start) - phase,
                amplitude: amplitude,
                period: period
            ) : 0)
        }
        .onChange(of: running) { _, now in
            if now {
                start = Date()
            }
        }
    }
}

struct MwPulseRing: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mwScale) private var scale

    func body(content: Content) -> some View {
        let running = isActive && !reduceMotion
        content.background {
            if running {
                TimelineView(.animation(minimumInterval: MwMotion.ambientFrameInterval)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: MwMotion.pulsePeriod) / MwMotion
                        .pulsePeriod
                    let spread = 14 * scale * phase
                    RoundedRectangle(cornerRadius: cornerRadius + spread, style: .circular)
                        .stroke(color, lineWidth: 2)
                        .padding(-spread)
                        .opacity(0.45 * (1 - phase))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
