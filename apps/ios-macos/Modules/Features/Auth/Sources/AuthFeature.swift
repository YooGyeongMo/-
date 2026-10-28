import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// AuthFeature 모듈(ADR-0016). 서버·Keychain을 모르고, 버튼이 눌렸다는 사실만 Composition에 넘긴다.
public enum AuthFeatureModule {
    public static let name = "AuthFeature"
}

/// S-01의 Apple 외 로그인. 계약 enum에는 있지만 서버는 v1.0에서 400을 낸다(ADR-0014, #90).
public enum OtherSignInProvider: String, CaseIterable, Sendable {
    case kakao
    case google
}

/// S-01 수치(Figma 51:468, 393×852pt). 화면에 쓰는 모든 크기는 여기 값 × 기기 배율이다.
nonisolated enum S01Spec {
    static let frame = CGSize(width: 393, height: 852)
    static let heroHeight: CGFloat = 470 // 51:469
    static let sideInset: CGFloat = 20 // 51:533·51:541 px-20
    static let contentWidth: CGFloat = 353
    static let titleTop: CGFloat = 22 // 51:533 pt-22
    static let titleSize: CGFloat = 28 // 51:535 Pretendard ExtraBold
    static let titleLineHeight: CGFloat = 38
    static let titleTracking: CGFloat = -0.56
    static let subtitleTop: CGFloat = 4 // 51:537 pt-4
    static let subtitleSize: CGFloat = 17 // 51:538 Pretendard Regular
    static let subtitleLineHeight: CGFloat = 26
    static let buttonsBottom: CGFloat = 42 // 51:541 pb-42 (홈 인디케이터 영역 포함, 화면 아래 끝 기준)
    static let buttonHeight: CGFloat = 56
    static let buttonGap: CGFloat = 10
    static let buttonRadius: CGFloat = 18
    static let buttonIconGap: CGFloat = 8
    static let buttonTextSize: CGFloat = 17 // Pretendard SemiBold
    static let paperGrain: CGFloat = 160 // 51:561
    /// 넓은 화면 오른쪽 열 위 로고(Figma에 없는 값, 넓은 화면 전용).
    static let wideLogo: CGFloat = 56
    /// Figma에 없는 값: 화면이 낮을 때(SE 등) 부제와 버튼 사이 최소 간격, 히어로 최소 높이.
    static let minimumGap: CGFloat = 24
    static let minimumHero: CGFloat = 220

    /// 기기 배율. 너비 기준(현재 iPhone 라인업은 화면 비율이 2.16~2.17로 Figma 393×852와 같다).
    static func scale(forWidth width: CGFloat) -> CGFloat {
        width > 0 ? width / frame.width : 1
    }
}

/// S-01 로그인(Figma 51:468).
///
/// Figma 393×852를 기기 너비에 맞춰 같은 비율로 키우거나 줄인다(모든 pt × 너비/393).
/// 세로로 남거나 모자라는 높이는 Figma의 늘어나는 칸(51:533, 제목 아래)이 받는다.
/// 그래도 모자라면(SE처럼 낮은 화면) 히어로가 줄고, 아주 큰 글자에서는 스크롤된다.
public struct AuthRootView: View {
    let isSigningIn: Bool
    let errorMessage: String?
    let onApple: () -> Void

    @State private var pendingProvider: OtherSignInProvider?
    /// 글자 크기 설정 배수. 기본(큰 글씨 끔)에서 1 → Figma와 같은 크기.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    public init(isSigningIn: Bool = false, errorMessage: String? = nil, onApple: @escaping () -> Void = {}) {
        self.isSigningIn = isSigningIn
        self.errorMessage = errorMessage
        self.onApple = onApple
    }

    @Environment(\.mwLayout) private var layout
    /// 글·버튼이 차례로 떠오르는 입장 연출(ADR-0024). 끝나면 Figma 자리 그대로다.
    @State private var isIn = false

    public var body: some View {
        Group {
            if layout == .wide {
                wideBody
            } else {
                compactBody
            }
        }
        .onAppear { isIn = true }
    }

    /// 넓은 화면(Mac·iPad): 왼쪽은 S-01 히어로가 꽉 찬 패널, 오른쪽은 로고·제목·버튼 열.
    private var wideBody: some View {
        HStack(spacing: 0) {
            MwIllustration.loginHero
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)
                MwIllustration.brandLogo
                    .frame(width: S01Spec.wideLogo, height: S01Spec.wideLogo)
                    .mwPop(isIn, tilt: -10)
                title(scale: 1)
                    .padding(.top, 20)
                    .mwRise(isIn, index: 1)
                subtitle(scale: 1)
                    .padding(.top, S01Spec.subtitleTop)
                    .mwRise(isIn, index: 2)
                Spacer(minLength: 32)
                buttons(scale: 1)
                    .mwRise(isIn, index: 3)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(width: 440)
            .frame(maxHeight: .infinity)
            .background(MwColor.brandPanel.ignoresSafeArea())
        }
        .overlay(alignment: .topLeading) {
            MwIllustration.paperGrain
                .frame(width: S01Spec.paperGrain, height: S01Spec.paperGrain)
                .ignoresSafeArea()
        }
    }

    private var compactBody: some View {
        GeometryReader { proxy in
            let scale = S01Spec.scale(forWidth: proxy.size.width)
            ScrollView {
                S01Layout(screenHeight: proxy.size.height, scale: scale) {
                    MwIllustration.loginHero
                    title(scale: scale).mwRise(isIn, index: 0)
                    subtitle(scale: scale).mwRise(isIn, index: 1)
                    buttons(scale: scale).mwRise(isIn, index: 2)
                }
                .overlay(alignment: .topLeading) {
                    MwIllustration.paperGrain
                        .frame(width: S01Spec.paperGrain * scale, height: S01Spec.paperGrain * scale)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea()
        .background(MwColor.brandPanel)
    }

    // MARK: - 글자

    private func font(_ weight: MwFont.Weight, _ size: CGFloat, _ scale: CGFloat) -> Font {
        MwFont.pretendard(weight, size: size * scale * typeScale)
    }

    /// "뭔말인교?" — 물음표만 Figma 파랑(#2F6FD6). VoiceOver는 한 단어로 읽는다.
    private func title(scale: CGFloat) -> some View {
        (Text("auth.signIn.wordmark", bundle: .module).foregroundStyle(MwColor.textPrimary)
            + Text(verbatim: "?").foregroundStyle(MwColor.accentFill))
            .font(font(.extraBold, S01Spec.titleSize, scale))
            .tracking(S01Spec.titleTracking * scale * typeScale)
            .lineSpacing(Self.extraLeading(lineHeight: S01Spec.titleLineHeight, size: S01Spec.titleSize) * scale * typeScale)
            .frame(minHeight: S01Spec.titleLineHeight * scale * typeScale)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func subtitle(scale: CGFloat) -> some View {
        Text("auth.signIn.subtitle", bundle: .module)
            .font(font(.regular, S01Spec.subtitleSize, scale))
            .foregroundStyle(MwColor.textSecondary)
            .lineSpacing(Self.extraLeading(lineHeight: S01Spec.subtitleLineHeight, size: S01Spec.subtitleSize) * scale * typeScale)
            .frame(minHeight: S01Spec.subtitleLineHeight * scale * typeScale)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// CSS line-height와 글꼴 기본 줄 높이(Pretendard ≈ 1.193em)의 차이. 여러 줄일 때 줄 간격으로 쓴다.
    static func extraLeading(lineHeight: CGFloat, size: CGFloat) -> CGFloat {
        max(lineHeight - size * 1.193, 0)
    }

    // MARK: - 버튼

    private func buttons(scale: CGFloat) -> some View {
        VStack(spacing: S01Spec.buttonGap * scale) {
            SignInButton(kind: .apple, scale: scale, typeScale: typeScale, isBusy: isSigningIn) {
                pendingProvider = nil
                onApple()
            }
            .disabled(isSigningIn)
            SignInButton(kind: .kakao, scale: scale, typeScale: typeScale) { pendingProvider = .kakao }
            SignInButton(kind: .google, scale: scale, typeScale: typeScale) { pendingProvider = .google }
        }
        // 안내·오류 문구는 Figma에 없다 → 배치를 밀지 않도록 버튼 위 빈 칸에 겹쳐 띄운다.
        .overlay(alignment: .top) {
            message(scale: scale)
                .alignmentGuide(.top) { $0[.bottom] + 12 * scale }
        }
    }

    @ViewBuilder private func message(scale: CGFloat) -> some View {
        if let provider = pendingProvider {
            Label(String(localized: String.LocalizationValue(Self.comingSoonKey(provider)), bundle: .module), systemImage: "clock")
                .font(font(.regular, 13, scale))
                .foregroundStyle(MwColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(font(.regular, 13, scale))
                .foregroundStyle(MwColor.urgentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    static func comingSoonKey(_ provider: OtherSignInProvider) -> String {
        switch provider {
        case .kakao: "auth.signIn.kakao.comingSoon"
        case .google: "auth.signIn.google.comingSoon"
        }
    }
}

/// S-01 배치. Figma 좌표를 배율만 곱해 그대로 놓는다.
/// - 히어로: 위 0, 높이 470
/// - 제목: 히어로 아래 22, 부제: 제목 아래 4
/// - 버튼 묶음: 화면 아래 끝에서 42 위
/// 남는 높이는 부제와 버튼 사이가 받는다(Figma 51:533 flex). 최소 간격 24가 안 나오면 히어로를 220까지 줄이고,
/// 그래도 모자라면 전체 높이가 화면보다 커져 스크롤된다.
struct S01Layout: Layout {
    let screenHeight: CGFloat
    let scale: CGFloat

    struct Frames: Equatable {
        var hero: CGRect
        var title: CGRect
        var subtitle: CGRect
        var buttons: CGRect
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? S01Spec.frame.width * scale
        return CGSize(width: width, height: frames(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 4 else { return }
        let frames = frames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, [frames.hero, frames.title, frames.subtitle, frames.buttons]) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> Frames {
        guard subviews.count == 4 else { return Frames(hero: .zero, title: .zero, subtitle: .zero, buttons: .zero, height: 0) }
        let content = width - S01Spec.sideInset * 2 * scale
        func height(_ index: Int) -> CGFloat {
            subviews[index].sizeThatFits(ProposedViewSize(width: content, height: nil)).height
        }
        let measured = Measured(title: height(1), subtitle: height(2), buttons: height(3))
        return Self.frames(width: width, screenHeight: screenHeight, scale: scale, measured: measured)
    }

    /// 측정값만으로 위치를 계산한다(테스트에서 직접 부른다).
    /// 글자 크기에 따라 달라지는 높이(제목·부제·버튼 묶음).
    struct Measured {
        var title: CGFloat
        var subtitle: CGFloat
        var buttons: CGFloat
    }

    static func frames(width: CGFloat, screenHeight: CGFloat, scale: CGFloat, measured: Measured) -> Frames {
        let (title, subtitle, buttons) = (measured.title, measured.subtitle, measured.buttons)
        let inset = S01Spec.sideInset * scale
        let content = width - inset * 2
        let textBlock = S01Spec.titleTop * scale + title + S01Spec.subtitleTop * scale + subtitle
        let bottomBlock = buttons + S01Spec.buttonsBottom * scale
        let naturalHero = S01Spec.heroHeight * scale
        let room = screenHeight - textBlock - S01Spec.minimumGap * scale - bottomBlock
        let hero = min(naturalHero, max(room, min(S01Spec.minimumHero * scale, naturalHero)))
        let height = max(screenHeight, hero + textBlock + S01Spec.minimumGap * scale + bottomBlock)
        let titleY = hero + S01Spec.titleTop * scale
        let subtitleY = titleY + title + S01Spec.subtitleTop * scale
        return Frames(
            hero: CGRect(x: 0, y: 0, width: width, height: hero),
            title: CGRect(x: inset, y: titleY, width: content, height: title),
            subtitle: CGRect(x: inset, y: subtitleY, width: content, height: subtitle),
            buttons: CGRect(x: inset, y: height - S01Spec.buttonsBottom * scale - buttons, width: content, height: buttons),
            height: height
        )
    }
}

#if DEBUG
    #Preview("S-01") { AuthRootView() }
    #Preview("S-01 오류") { AuthRootView(errorMessage: "로그인에 실패했어요. 다시 시도해 주세요.") }
#endif
