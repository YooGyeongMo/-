import MwonmalUI
import SwiftUI

/// 그림 한 장. 쪽이 바뀌면 `.id`가 바뀌어 다이브 전환으로 갈아 끼운다. 나타난 뒤에 칩들이 움직이기 시작한다.
struct OnboardingScene: View {
    let page: OnboardingPage
    let forward: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingSceneContent(page: page)
                .id(page.index)
                .transition(.mwDive(forward: forward, reduceMotion: reduceMotion))
        }
        .clipped()
    }
}

private struct OnboardingSceneContent: View {
    let page: OnboardingPage
    @State private var isActive = false

    var body: some View {
        OnboardingIllustration(page: page.index, isActive: isActive) { geometry in
            switch page.index {
            case 1: PasteSourcesChip(geometry: geometry, isIn: isActive)
            case 2: NoticeCards(geometry: geometry, isIn: isActive)
            default: EmptyView()
            }
        }
        .onAppear { isActive = true }
    }
}

/// 윗줄·제목·본문(Figma 51:146~51:153). 줄마다 차례로 떠오른다. VoiceOver는 한 덩어리로 읽는다.
struct OnboardingCopy: View {
    let page: OnboardingPage
    @State private var isIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.eyebrow, bundle: .module)
                .mwFont(.bold, 14, lineHeight: 20, tracking: -0.07)
                .foregroundStyle(page.accent.color)
                .mwRise(isIn, index: 0)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.titleLines.enumerated()), id: \.offset) { offset, line in
                    Text(line, bundle: .module)
                        .mwFont(.bold, 28, lineHeight: 38, tracking: -0.56)
                        .foregroundStyle(MwColor.textPrimary)
                        .mwRise(isIn, index: offset + 1)
                }
            }
            .padding(.top, OnboardingSpec.titleTop.s(scale))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(page.body, bundle: .module)
                .mwFont(.regular, 17, lineHeight: 26)
                .foregroundStyle(MwColor.textSecondary)
                .padding(.top, OnboardingSpec.bodyTop.s(scale))
                .mwRise(isIn, index: page.titleLines.count + 1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isIn = true }
    }

    @Environment(\.mwScale) private var scale
}

/// 점 3개 + 다음/시작하기(Figma 51:157). 마지막 쪽 버튼은 파란 주 버튼이고, 둘레로 옅은 물결이 퍼진다.
struct OnboardingControls: View {
    let index: Int
    let isLast: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.mwScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            dots
            Button(action: onNext) {
                Text(isLast ? "onboarding.start" : "onboarding.next", bundle: .module)
                    .mwFont(.semiBold, 17)
                    .contentTransition(.opacity)
            }
            .buttonStyle(OnboardingButtonStyle(isPrimary: isLast))
            .mwPulseRing(isLast, cornerRadius: OnboardingSpec.buttonRadius * scale, color: MwColor.accentFill)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(isLast ? "onboarding.start" : "onboarding.next")
            .padding(.top, OnboardingSpec.dotsToButton * scale)
        }
    }

    private var dots: some View {
        HStack(spacing: 6 * scale) {
            ForEach(0 ..< OnboardingPage.all.count, id: \.self) { dot in
                Capsule()
                    .fill(MwColor.textPrimary.opacity(dot == index ? 1 : 0.18))
                    .frame(
                        width: (dot == index ? OnboardingSpec.activeDot : OnboardingSpec.dot) * scale,
                        height: OnboardingSpec.dot * scale
                    )
            }
        }
        .animation(MwMotion.spring(.snappy, reduceMotion: reduceMotion), value: index)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.progress", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(index + 1) / \(OnboardingPage.all.count)"))
    }
}

/// 다음(어두운 버튼, Figma 51:162: #1F1A2E, 아래 2pt 검정, 0 8 18 25%) ↔ 시작하기(파란 주 버튼 51:445).
struct OnboardingButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.mwScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingSpec.buttonRadius * scale, style: .circular)
        configuration.label
            .foregroundStyle(isPrimary ? MwColor.accentOnFill : MwColor.canvas)
            .frame(maxWidth: .infinity, minHeight: OnboardingSpec.buttonHeight * scale)
            .background(shape.fill(isPrimary ? MwColor.accentFill : MwColor.textPrimary))
            .background(shape.fill(isPrimary ? MwColor.accentShadow : Color.black).offset(y: 2 * scale))
            .shadow(
                color: (isPrimary ? MwColor.accentFill : MwColor.textPrimary).opacity(isPrimary ? 0.28 : 0.25),
                radius: 9 * scale,
                y: 8 * scale
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .offset(y: configuration.isPressed ? 1 * scale : 0)
            .contentShape(shape)
            .animation(MwMotion.spring(.snappy, reduceMotion: reduceMotion), value: isPrimary)
    }
}

/// 건너뛰기(Figma 51:141): 유리 알약, 높이 40, 좌우 16, Pretendard SemiBold 16.
struct OnboardingSkipButton: View {
    let action: () -> Void
    @Environment(\.mwScale) private var scale

    var body: some View {
        Button(action: action) {
            Text("onboarding.skip", bundle: .module)
                .mwFont(.semiBold, 16)
                .foregroundStyle(MwColor.textPrimary)
                .padding(.horizontal, 16 * scale)
                .frame(minHeight: OnboardingSpec.skipHeight * scale)
                .background(MwGlassBackground(cornerRadius: OnboardingSpec.skipHeight / 2, fill: MwColor.glassFillThin))
                .mwGlassShadow(scale, y: 4, blur: 14, opacity: 0.1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("onboarding.skip")
    }
}
