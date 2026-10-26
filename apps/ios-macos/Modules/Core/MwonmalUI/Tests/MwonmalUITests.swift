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
