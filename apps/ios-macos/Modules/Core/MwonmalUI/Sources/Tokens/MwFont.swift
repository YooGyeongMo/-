import CoreText
import SwiftUI

/// Pretendard(OFL 1.1, v1.3.9, `Resources/Fonts/Pretendard-LICENSE.txt`). Figma 본문 글꼴.
///
/// 정적 프레임워크 리소스 번들에 들어 있어 Info.plist `UIAppFonts`로는 못 찾는다 → 처음 쓸 때 프로세스 범위로 등록한다.
/// 크기는 호출하는 쪽이 정한다(Figma pt × 기기 배율 × 글자 크기 설정). 그래서 `fixedSize`로 만든다.
public enum MwFont {
    public enum Weight: String, CaseIterable, Sendable {
        case regular = "Pretendard-Regular"
        case medium = "Pretendard-Medium"
        case semiBold = "Pretendard-SemiBold"
        case bold = "Pretendard-Bold"
        case extraBold = "Pretendard-ExtraBold"
    }

    public static func pretendard(_ weight: Weight, size: CGFloat) -> Font {
        _ = registered
        return .custom(weight.rawValue, fixedSize: size)
    }

    /// 등록이 끝났는지(테스트용). 이미 등록된 경우도 성공으로 본다.
    static let registered: Bool = Weight.allCases.allSatisfy { weight in
        guard let url = Bundle.module.url(forResource: weight.rawValue, withExtension: "otf") else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            return true
        }
        // 이미 등록됨(kCTFontManagerErrorAlreadyRegistered = 105)은 성공.
        let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
        return code == CTFontManagerError.alreadyRegistered.rawValue
    }
}
