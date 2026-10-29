import SwiftUI

/// 앱을 켤 때의 시작 연출(레퍼런스 V2, ADR-0024). 첫 프레임은 시스템 실행 화면(종이색 + 가운데 로고 96pt)과 똑같다.
///
/// 1. 로고가 한 번 눌렸다 튀어 오른다(0.15초 뒤).
/// 2. 화면 전체를 덮던 종이 면이 찌그러지며 가운데 둥근 타일(아이콘 크기)로 접힌다.
/// 3. 타일이 사라지는 동안 뒤의 첫 화면이 흐림에서 초점으로 들어온다(`mwFocusIn`).
///
/// 전체 1.2초. 로딩을 기다리게 하지 않는다 — 뒤에서는 세션 복원이 그대로 돈다. 터치는 막지 않는다.
/// 동작 줄이기면 0.25초 뒤 페이드로만 사라진다.
public struct MwLaunchSplash<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var phase: Phase = .cover
    @Environment(\.mwReduceMotion) private var reduceMotion

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    enum Phase: Int, Comparable {
        case cover, pop, fold, gone

        static func < (lhs: Phase, rhs: Phase) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var body: some View {
        ZStack {
            content
                .mwFocusIn(phase >= .fold, delay: 0.05)
            if phase < .gone {
                cover
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .task { await run() }
    }

    private var cover: some View {
        GeometryReader { proxy in
            let folded = phase >= .fold
            let width = folded ? MwLaunchSplashSpec.tileSize : proxy.size.width
            let height = folded ? MwLaunchSplashSpec.tileSize : proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: folded ? MwLaunchSplashSpec.tileRadius : 0, style: .continuous)
                    .fill(MwColor.canvas)
                    .shadow(color: .black.opacity(folded ? 0.18 : 0), radius: 24, y: 12)
                    .frame(width: width, height: height)
                MwIllustration.brandLogo
                    .frame(width: MwLaunchSplashSpec.logoSize, height: MwLaunchSplashSpec.logoSize)
                    .scaleEffect(logoScale, anchor: .center)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(folded ? 0.92 : 1)
        }
        .ignoresSafeArea()
    }

    private var logoScale: CGFloat {
        switch phase {
        case .cover: 1
        case .pop: 1.08
        case .fold, .gone: 0.86
        }
    }

    private func run() async {
        guard phase == .cover else { return }
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(MwMotion.spring(.soft, reduceMotion: true)) { phase = .gone }
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(MwMotion.spring(.pop, reduceMotion: false)) { phase = .pop }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(MwMotion.spring(.squash, reduceMotion: false)) { phase = .fold }
        try? await Task.sleep(for: .milliseconds(480))
        withAnimation(MwMotion.spring(.soft, reduceMotion: false)) { phase = .gone }
    }
}

/// 시작 연출 수치. 제네릭 뷰에는 정적 저장 속성을 둘 수 없어 따로 둔다.
public enum MwLaunchSplashSpec {
    /// 실행 화면 로고 크기(앱 Assets `LaunchLogo`의 pt 크기와 같아야 첫 프레임이 이어진다).
    public static let logoSize: CGFloat = 96
    /// 접힌 타일 크기·모서리(홈 화면 아이콘 모서리 비율 약 0.225).
    static let tileSize: CGFloat = 132
    static let tileRadius: CGFloat = 30
}
