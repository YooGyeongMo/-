import CoreGraphics
import Foundation
@testable import OnboardingFeature
import Testing

struct OnboardingFeatureTests {
    @Test("모듈 이름") func moduleName() {
        #expect(OnboardingFeatureModule.name == "OnboardingFeature")
    }

    @Test("쪽 3개, 마지막만 시작하기") func pages() {
        #expect(OnboardingPage.all.count == 3)
        #expect(OnboardingPage.all.map(\.index) == [0, 1, 2])
        #expect(OnboardingPage.all.map(\.isLast) == [false, false, true])
        #expect(OnboardingPage.all.allSatisfy { $0.titleLines.count == 2 })
    }

    @Test("쪽에 쓰는 문구 키가 모두 카탈로그에 있다") func catalogKeys() throws {
        let url = try #require(Self.catalogInSource())
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = Set((catalog?["strings"] as? [String: Any])?.keys.map(\.self) ?? [])
        let needed = ["onboarding.skip", "onboarding.next", "onboarding.start", "onboarding.progress", "onboarding.page2.sources"]
            + (1 ... 3).flatMap { [
                "onboarding.page\($0).eyebrow",
                "onboarding.page\($0).title1",
                "onboarding.page\($0).title2",
                "onboarding.page\($0).body",
            ] }
        for key in needed {
            #expect(keys.contains(key), "\(key) 없음")
        }
    }

    /// 빌드된 번들에는 .xcstrings가 .strings로 바뀌어 들어가므로 소스 파일을 직접 읽는다.
    static func catalogInSource() -> URL? {
        let here = URL(fileURLWithPath: #filePath)
        let url = here.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localizable.xcstrings")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// O-1~O-3 그림 높이: Figma 500 × 배율이 기본, 낮은 화면에서는 줄되 240 × 배율 밑으로는 안 간다.
struct OnboardingLayoutTests {
    /// Figma 글 블록(26 + 20 + 6 + 76 + 8 + 26 = 162)과 아래 블록(10 + 7 + 22 + 56 + 42 = 137).
    static let copy: CGFloat = 162
    static let footer: CGFloat = 137

    @Test("393×852: 그림 500 그대로") func figma() {
        #expect(OnboardingSpec.heroHeight(screenHeight: 852, copyHeight: Self.copy, footerHeight: Self.footer, scale: 1) == 500)
    }

    @Test("SE(375×667): 그림이 줄어 글·버튼이 한 화면에 들어간다") func shortScreen() {
        let scale: CGFloat = 375 / 393
        let hero = OnboardingSpec.heroHeight(
            screenHeight: 667,
            copyHeight: Self.copy * scale,
            footerHeight: Self.footer * scale,
            scale: scale
        )
        #expect(hero < 500 * scale)
        #expect(hero + Self.copy * scale + Self.footer * scale + OnboardingSpec.minimumGap * scale <= 667.001)
    }

    @Test("아주 큰 글자: 그림은 240 × 배율에서 멈춘다(나머지는 스크롤)") func hugeText() {
        let hero = OnboardingSpec.heroHeight(screenHeight: 852, copyHeight: 600, footerHeight: 300, scale: 1)
        #expect(hero == OnboardingSpec.minimumHero)
    }
}
