@testable import AuthFeature
import Foundation
import Testing

struct AuthFeatureTests {
    @Test("모듈 이름") func moduleName() {
        #expect(AuthFeatureModule.name == "AuthFeature")
    }

    @Test("카카오·Google은 각자 안내 문구가 있다") func comingSoonKeys() {
        let keys = OtherSignInProvider.allCases.map(AuthRootView.comingSoonKey)
        #expect(Set(keys).count == OtherSignInProvider.allCases.count)
    }
}

/// Figma 51:468 좌표가 기기마다 같은 비율로 나오는지. 글자 높이는 Figma 줄 높이(38·26)와 버튼 묶음(56×3+10×2)을 넣는다.
struct S01LayoutTests {
    static func figmaFrames(width: CGFloat, height: CGFloat) -> S01Layout.Frames {
        let scale = S01Spec.scale(forWidth: width)
        return S01Layout.frames(
            width: width,
            screenHeight: height,
            scale: scale,
            measured: .init(title: 38 * scale, subtitle: 26 * scale, buttons: 188 * scale)
        )
    }

    @Test("393×852에서 Figma 좌표와 정확히 같다") func figmaFrame() {
        let frames = Self.figmaFrames(width: 393, height: 852)
        #expect(frames.hero == CGRect(x: 0, y: 0, width: 393, height: 470))
        #expect(frames.title == CGRect(x: 20, y: 492, width: 353, height: 38)) // 470 + 22
        #expect(frames.subtitle == CGRect(x: 20, y: 534, width: 353, height: 26)) // 470 + 60 + 4
        #expect(frames.buttons == CGRect(x: 20, y: 622, width: 353, height: 188)) // 612 + 10
        #expect(frames.height == 852)
    }

    /// 현재 iPhone 라인업(16e·16·16 Plus·17·17 Pro·Air·17 Pro Max). 모든 좌표가 Figma × (너비/393)에서 1pt 안쪽.
    @Test("현재 iPhone은 Figma를 같은 비율로 키운 모양", arguments: [
        (390.0, 844.0), (393.0, 852.0), (402.0, 874.0), (420.0, 912.0), (430.0, 932.0), (440.0, 956.0),
    ])
    func proportional(width: Double, height: Double) {
        let scale = width / 393
        let frames = Self.figmaFrames(width: width, height: height)
        #expect(abs(frames.hero.height - 470 * scale) < 0.001)
        #expect(abs(frames.title.minY - 492 * scale) < 0.001)
        #expect(abs(frames.subtitle.minY - 534 * scale) < 0.001)
        // 버튼은 화면 아래에서 42 × 배율. 기기 화면 비율이 Figma(852/393)와 미세하게 달라 남는 높이
        // (17 Pro 2.5pt, Pro Max 2.1pt)는 Figma처럼 제목 아래 늘어나는 칸(51:533)이 받는다.
        #expect(abs((height - frames.buttons.maxY) - 42 * scale) < 0.001)
        #expect(abs(frames.buttons.minY - 622 * scale - (height - 852 * scale)) < 0.001)
        #expect(abs(frames.height - height) < 0.001)
    }

    @Test("iPhone SE(375×667): 히어로만 줄고 나머지는 같은 비율, 스크롤 없음") func shortScreen() {
        let scale = 375.0 / 393
        let frames = Self.figmaFrames(width: 375, height: 667)
        #expect(abs(frames.height - 667) < 0.001)
        #expect(frames.hero.height < 470 * scale)
        #expect(abs(frames.buttons.minY - frames.subtitle.maxY - 24 * scale) < 0.001)
    }

    @Test("아주 큰 글자: 히어로는 최소 220×배율, 넘치면 스크롤") func hugeText() {
        let scale = 375.0 / 393
        let frames = S01Layout.frames(width: 375, screenHeight: 667, scale: scale, measured: .init(title: 200, subtitle: 300, buttons: 500))
        #expect(abs(frames.hero.height - 220 * scale) < 0.001)
        #expect(frames.height > 667)
    }
}
