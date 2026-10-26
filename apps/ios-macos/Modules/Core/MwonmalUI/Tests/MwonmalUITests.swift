import CoreGraphics
@testable import MwonmalUI
import Testing

#if canImport(UIKit)
    import UIKit

    /// ADR-0017: 토큰이 4벌 모두 있고, 핵심 글자·배경 쌍이 WCAG 기준을 넘는지 Asset Catalog 실제 값으로 잰다.
    @MainActor
    struct ColorTokenTests {
        /// iOS 17 가변 트레잇 이니셜라이저. `traitsFrom:`로 합치면 스타일이 지정 안 됨으로 덮여 라이트만 나온다.
        static func traits(_ style: UIUserInterfaceStyle, _ contrast: UIAccessibilityContrast) -> UITraitCollection {
            UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.accessibilityContrast = contrast
            }
        }

        static let traits: [(String, UITraitCollection)] = [
            ("light", traits(.light, .normal)),
            ("dark", traits(.dark, .normal)),
            ("lightHC", traits(.light, .high)),
            ("darkHC", traits(.dark, .high)),
        ]

        @Test("모드마다 다른 값이 나온다(트레잇 적용 확인)") func traitsApply() throws {
            let values = try Self.traits.map { try #require(Self.color("text.secondary", $0.1)).resolvedColor(with: $0.1) }
            #expect(Set(values.map(\.description)).count == 4)
        }

        static func color(_ name: String, _ traits: UITraitCollection) -> UIColor? {
            UIColor(named: name, in: .module, compatibleWith: traits)?.resolvedColor(with: traits)
        }

        static func luminance(_ color: UIColor) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func channel(_ value: CGFloat) -> Double {
                let linear = Double(value)
                return linear <= 0.039_28 ? linear / 12.92 : pow((linear + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        static func contrast(_ lhs: UIColor, _ rhs: UIColor) -> Double {
            let (high, low) = (max(luminance(lhs), luminance(rhs)), min(luminance(lhs), luminance(rhs)))
            return (high + 0.05) / (low + 0.05)
        }

        @Test("토큰 22개가 모두 번들에 있다") func allTokensResolve() {
            for name in MwColor.allNames {
                for (_, traits) in Self.traits {
                    #expect(Self.color(name, traits) != nil, "\(name) 없음")
                }
            }
        }

        @Test("본문 글자 4.5:1, 고대비 7:1", arguments: [
            ("text.primary", "bg.canvas"), ("text.primary", "bg.surface"), ("text.primary", "bg.brandPanel"),
            ("text.secondary", "bg.canvas"), ("text.secondary", "bg.surface"), ("text.secondary", "bg.brandPanel"),
            ("accent.text", "bg.canvas"), ("accent.text", "bg.surface"),
            ("accent.onFill", "accent.fill"),
            ("status.urgentText", "status.urgentFill"), ("status.soonText", "status.soonFill"),
            ("status.doneText", "status.doneFill"), ("jargon.chipText", "jargon.chipFill"),
        ])
        func textContrast(_ foreground: String, _ background: String) throws {
            for (mode, traits) in Self.traits {
                let ratio = try Self.contrast(#require(Self.color(foreground, traits)), #require(Self.color(background, traits)))
                let minimum = mode.hasSuffix("HC") && foreground.hasPrefix("text.") ? 7.0 : 4.5
                #expect(ratio >= minimum, "\(foreground)/\(background) \(mode) = \(ratio)")
            }
        }

        @Test("UI 요소 3:1(테두리·형광펜 밑줄)", arguments: [
            ("control.border", "bg.surface"), ("control.border", "bg.canvas"), ("jargon.underline", "bg.surface"),
        ])
        func uiContrast(_ foreground: String, _ background: String) throws {
            for (mode, traits) in Self.traits {
                let ratio = try Self.contrast(#require(Self.color(foreground, traits)), #require(Self.color(background, traits)))
                #expect(ratio >= 3.0, "\(foreground)/\(background) \(mode) = \(ratio)")
            }
        }
    }
#endif

struct MwonmalUIModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(MwonmalUIModule.name == "MwonmalUI")
    }
}

/// S-01 히어로 레이어 배치(Figma 51:470). 화면 비율이 달라도 빈틈 없이 채우는지.
struct LoginHeroLayoutTests {
    @Test("Figma 크기(393×470)에서는 배율 1, 무대가 화면과 딱 맞는다") func figmaSize() {
        let size = CGSize(width: 393, height: 470)
        #expect(LoginHeroIllustration.scale(for: size) == 1)
        #expect(LoginHeroIllustration.stageOrigin(for: size, scale: 1) == .zero)
    }

    @Test("낮은 화면: 높이에 맞춰 줄고, 무대는 가운데·바닥에 붙는다") func shortScreen() {
        let size = CGSize(width: 375, height: 300)
        let scale = LoginHeroIllustration.scale(for: size)
        #expect(abs(scale - 300.0 / 470.0) < 0.0001)
        let origin = LoginHeroIllustration.stageOrigin(for: size, scale: scale)
        #expect(abs(origin.y) < 0.0001)
        #expect(origin.x > 0)
    }

    @Test("큰 화면: 상한 1.6배를 넘지 않는다") func largeScreen() {
        #expect(LoginHeroIllustration.scale(for: CGSize(width: 1024, height: 1366)) == LoginHeroIllustration.maxScale)
    }

    @Test("크기 0이면 배율 0(나눗셈 오류 없음)") func zeroSize() {
        #expect(LoginHeroIllustration.scale(for: .zero) == 0)
    }

    @Test("레이어가 무대 393×470 안쪽(땅 제외)에 있다") func layersInsideStage() {
        let stage = CGRect(origin: .zero, size: LoginHeroIllustration.stage)
        for layer in LoginHeroIllustration.layers {
            #expect(stage.contains(layer.frame), "\(layer.name)")
        }
    }

    #if canImport(UIKit)
        @Test("레이어 에셋이 모두 번들에 있다") func assetsResolve() {
            let names = LoginHeroIllustration.layers.map(\.name) + ["LoginHeroGround"]
            for name in names {
                #expect(UIImage(named: name, in: .module, compatibleWith: nil) != nil, "\(name)")
            }
            #expect(UIColor(named: "LoginHeroSky", in: .module, compatibleWith: nil) != nil)
        }
    #endif
}

struct MwFontTests {
    @Test("Pretendard 3종(Regular·SemiBold·ExtraBold)이 번들에 있고 등록된다") func registers() {
        #expect(MwFont.registered)
    }

    #if canImport(UIKit)
        @Test("등록 뒤 이름으로 찾을 수 있다", arguments: MwFont.Weight.allCases)
        func resolves(weight: MwFont.Weight) {
            _ = MwFont.registered
            #expect(UIFont(name: weight.rawValue, size: 17) != nil)
        }
    #endif
}
