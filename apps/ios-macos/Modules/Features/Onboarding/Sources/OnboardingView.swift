import MwonmalUI
import SwiftUI

/// O-1~O-3 온보딩(Figma 51:18·51:178·51:301).
///
/// 좁은 화면(iPhone): Figma 393×852를 너비 비율로 그대로. 위 500은 그림, 아래는 글·점·버튼.
/// 넓은 화면(Mac·iPad): 왼쪽은 그림이 꽉 찬 패널, 오른쪽은 글·버튼 열(웹 W-01 같은 두 칸).
///
/// 움직임(ADR-0024): 다음 쪽으로 가면 그림이 "다이브"로 바뀌고(나가는 장면은 카메라를 지나치고 새 장면이 다가옴),
/// 글은 윗줄 → 제목 줄 → 본문 순서로 떠오른다. 칩·말풍선·알림 카드는 차례로 튀어나와 떠다닌다.
/// 옆으로 밀어도 넘어간다. Mac은 Return = 다음, Esc = 건너뛰기.
public struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var index = 0
    @State private var forward = true
    @Environment(\.mwLayout) private var layout
    @Environment(\.mwScale) private var scale
    @Environment(\.mwReduceMotion) private var reduceMotion

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    private var page: OnboardingPage {
        OnboardingPage.all[index]
    }

    public var body: some View {
        Group {
            if layout == .wide {
                wideBody
            } else {
                OnboardingCompactLayout(page: page, index: index, forward: forward, controls: controls)
            }
        }
        // 쪽마다 바탕색이 다르다(O-1 종이 · O-2 옅은 청록 · O-3 옅은 살구). 쪽 넘김과 같은 시간표로 바뀐다.
        .background(page.accent.panel.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            MwIllustration.paperGrain
                .frame(width: OnboardingSpec.paperGrain * scale, height: OnboardingSpec.paperGrain * scale)
                .ignoresSafeArea()
        }
        .gesture(swipe)
    }

    // MARK: - 넓은 화면

    private var wideBody: some View {
        HStack(spacing: 0) {
            OnboardingScene(page: page, forward: forward)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    skipButton
                }
                Spacer(minLength: 24)
                OnboardingCopy(page: page)
                    .id(page.index)
                    .transition(.opacity)
                Spacer(minLength: 24)
                controls
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
            .frame(width: 460)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - 조작

    var controls: OnboardingControls {
        OnboardingControls(
            index: index,
            isLast: page.isLast,
            onNext: next,
            onSkip: finish
        )
    }

    private var skipButton: some View {
        OnboardingSkipButton(action: finish)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height), abs(width) > 50 else { return }
                if width < 0 {
                    next()
                } else {
                    back()
                }
            }
    }

    private func next() {
        guard !page.isLast else { return finish() }
        forward = true
        withAnimation(MwMotion.page(reduceMotion: reduceMotion)) { index += 1 }
    }

    private func back() {
        guard index > 0 else { return }
        forward = false
        withAnimation(MwMotion.page(reduceMotion: reduceMotion)) { index -= 1 }
    }

    private func finish() {
        onFinish()
    }
}

/// 좁은 화면 배치. 그림 높이는 글·버튼을 재서 정한다(SE처럼 낮은 화면이면 그림이 240까지 준다).
struct OnboardingCompactLayout: View {
    let page: OnboardingPage
    let index: Int
    let forward: Bool
    let controls: OnboardingControls

    @Environment(\.mwScale) private var scale
    @State private var copyHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let hero = OnboardingSpec.heroHeight(screenHeight: screen, copyHeight: copyHeight, footerHeight: footerHeight, scale: scale)
            ScrollView {
                VStack(spacing: 0) {
                    OnboardingScene(page: page, forward: forward)
                        .frame(height: hero)
                        .overlay(alignment: .topTrailing) {
                            OnboardingSkipButton(action: controls.onSkip)
                                .frame(minHeight: OnboardingSpec.skipRow * scale)
                                .padding(.trailing, OnboardingSpec.skipInset * scale)
                                .padding(.top, proxy.safeAreaInsets.top)
                        }
                    OnboardingCopy(page: page)
                        .id(page.index)
                        .transition(.opacity)
                        .padding(.horizontal, OnboardingSpec.sideInset * scale)
                        .padding(.top, OnboardingSpec.copyTop * scale)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 + OnboardingSpec.copyTop * scale }
                    Spacer(minLength: OnboardingSpec.minimumGap * scale)
                    controls
                        .padding(.horizontal, OnboardingSpec.sideInset * scale)
                        .padding(.top, OnboardingSpec.dotsTop * scale)
                        .padding(.bottom, OnboardingSpec.bottomInset * scale)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                }
                .frame(minHeight: screen)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea()
        }
    }
}
