import SwiftUI

// 프리셋 3개의 모디파이어(ADR-0012 §4-1 표면 API). 값은 `@Environment(\.mwMotion)`에서 읽는다.
// 끝 상태에는 변형이 없다: 뒤집힌 카드는 뒷면 그대로, 맥박이 꺼지면 투명도·크기 1, 오버레이는 제자리.

public extension View {
    /// 카드 뒤집기. 이 뷰가 앞면, `back`이 뒷면이다. 동작 줄이기면 돌지 않고 짧게 겹쳐 바뀐다.
    /// VoiceOver는 보이는 면만 읽는다.
    func mwCardFlip(isFlipped: Bool, @ViewBuilder back: () -> some View) -> some View {
        MwCardFlip(isFlipped: isFlipped, front: self, back: back())
    }

    /// 해석 중 맥박. 꺼지면 바로 원래 모습. 동작 줄이기면 움직이지 않는다(진행 표시는 부르는 쪽이 둔다).
    func mwDecodingPulse(isActive: Bool) -> some View {
        modifier(MwDecodingPulse(isActive: isActive))
    }

    /// 앱이 그리는 아래 오버레이(토스트·안내 띠)가 나타나고 사라지는 모양. 시간표는 `MwMotion.sheet`로 감싼다.
    func mwSheetTransition() -> some View {
        modifier(MwSheetTransition())
    }
}

public extension AnyTransition {
    /// 아래에서 `travel`만큼 올라오며 나타난다. 동작 줄이기면 페이드만.
    static func mwSheet(_ spec: MwSheetPresentSpec, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .modifier(active: MwSheetOffset(y: spec.travel), identity: MwSheetOffset(y: 0)).combined(with: .opacity)
    }
}

struct MwSheetOffset: ViewModifier {
    let y: Double

    func body(content: Content) -> some View {
        content.offset(y: y)
    }
}

struct MwSheetTransition: ViewModifier {
    @Environment(\.mwMotion) private var theme
    @Environment(\.mwReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(.mwSheet(theme.sheetPresent, reduceMotion: reduceMotion))
    }
}

struct MwCardFlip<Front: View, Back: View>: View {
    let isFlipped: Bool
    let front: Front
    let back: Back
    @Environment(\.mwMotion) private var theme
    @Environment(\.mwReduceMotion) private var reduceMotion

    var body: some View {
        let spec = theme.cardFlip
        if reduceMotion {
            ZStack {
                front.opacity(isFlipped ? 0 : 1).accessibilityHidden(isFlipped)
                back.opacity(isFlipped ? 1 : 0).accessibilityHidden(!isFlipped)
            }
            .animation(spec.timing.animation(reduceMotion: true), value: isFlipped)
        } else {
            MwCardFlipFrame(progress: isFlipped ? 1 : 0, spec: spec, front: front, back: back)
                .animation(spec.timing.animation(reduceMotion: false), value: isFlipped)
        }
    }
}

/// 진행률을 프레임마다 받아(Animatable) 절반에서 면을 바꾼다. 시작·끝에서는 회전 0, 크기 1.
struct MwCardFlipFrame<Front: View, Back: View>: View, Animatable {
    var progress: Double
    let spec: MwCardFlipSpec
    let front: Front
    let back: Back

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showsBack = spec.showsBack(at: progress)
        ZStack {
            front.opacity(showsBack ? 0 : 1).accessibilityHidden(showsBack)
            back.opacity(showsBack ? 1 : 0).accessibilityHidden(!showsBack)
        }
        .rotation3DEffect(.degrees(spec.faceAngle(at: progress)), axis: (x: 0, y: 1, z: 0), perspective: spec.perspective)
        .scaleEffect(spec.lift(at: progress))
    }
}

struct MwDecodingPulse: ViewModifier {
    let isActive: Bool
    @Environment(\.mwMotion) private var theme
    @Environment(\.mwReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        let running = isActive && !reduceMotion
        let spec = theme.decodingPulse
        TimelineView(.animation(minimumInterval: MwMotion.ambientFrameInterval, paused: !running)) { context in
            let elapsed = running ? context.date.timeIntervalSince(start) : 0
            content
                .opacity(spec.opacity(at: elapsed))
                .scaleEffect(spec.scale(at: elapsed))
        }
        .onChange(of: running) { _, now in
            if now {
                start = Date()
            }
        }
    }
}
