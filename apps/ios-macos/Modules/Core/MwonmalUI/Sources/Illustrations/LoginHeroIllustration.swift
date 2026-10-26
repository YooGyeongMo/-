import SwiftUI

/// S-01 히어로(Figma 51:470). 통짜 그림 한 장 대신 레이어로 나눠 그린다.
///
/// 통짜 그림은 비율이 고정이라, 화면 비율이 Figma(393×470)와 다르면 양옆이나 위가 빈다.
/// 그래서 늘려도 되는 것과 안 되는 것을 나눴다.
/// - 하늘: 단색. 상태 바 밑과 넓은 화면 끝까지 채운다.
/// - 땅 5겹: 가로로만 늘린다. 물결이라 늘려도 티가 안 나고, 어떤 너비에서도 양끝에 닿는다.
/// - 해·말풍선·인물: 비율을 지킨 채 393×470 무대 안에서 함께 커지고 작아진다(가운데·바닥 정렬).
///
/// 레이어는 모두 Figma에서 받은 벡터(PDF·SVG) 에셋이다. 크기가 바뀔 때만 한 번 래스터화되고 캐시되므로
/// 매 프레임 Path를 그리는 방식보다 가볍고, PNG처럼 흐려지지도 않는다.
public struct LoginHeroIllustration: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = Self.scale(for: size)
            let origin = Self.stageOrigin(for: size, scale: scale)
            ZStack(alignment: .topLeading) {
                Color("LoginHeroSky", bundle: .module)
                Self.image("LoginHeroGround")
                    .frame(width: size.width + Self.groundOverhang * 2 * scale, height: Self.ground.height * scale)
                    .offset(x: -Self.groundOverhang * scale, y: origin.y + Self.ground.minY * scale)
                ForEach(Self.layers, id: \.name) { layer in
                    Self.image(layer.name)
                        .frame(width: layer.frame.width * scale, height: layer.frame.height * scale)
                        .offset(x: origin.x + layer.frame.minX * scale, y: origin.y + layer.frame.minY * scale)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: - 배치 (Figma 좌표, 393×470 무대 기준)

    struct Layer: Equatable {
        let name: String
        let frame: CGRect
    }

    static let stage = CGSize(width: 393, height: 470)
    /// iPad처럼 큰 화면에서 인물이 지나치게 커지지 않게 막는 상한.
    static let maxScale: CGFloat = 1.6
    /// 땅(51:474~478)은 무대 양옆으로 20씩 넘친다.
    static let groundOverhang: CGFloat = 20
    static let ground = CGRect(x: -20, y: 353.9, width: 433, height: 136.1)

    /// 뒤에 있는 것부터. 크기는 내려받은 PDF의 실제 크기(획 두께 포함),
    /// 위치는 Figma 통짜 렌더와 픽셀 매칭으로 맞췄다(0.25pt 단위).
    static let layers: [Layer] = [
        Layer(name: "LoginHeroSun", frame: CGRect(x: 26, y: 66, width: 88, height: 88)), // 51:472·473
        Layer(name: "LoginHeroBubbles", frame: CGRect(x: 112, y: 170, width: 202, height: 190)), // 51:479
        Layer(name: "LoginHeroPersonSitting", frame: CGRect(x: 229.5, y: 146.75, width: 39.045, height: 73.227)), // 51:487
        Layer(name: "LoginHeroPersonPhone", frame: CGRect(x: 137, y: 325.5, width: 33.081, height: 76.7)), // 51:496
        Layer(name: "LoginHeroPersonWave", frame: CGRect(x: 287.5, y: 320, width: 29.201, height: 86)), // 51:507
    ]

    /// 너비와 높이 중 빡빡한 쪽에 맞춘다. 남는 쪽은 하늘과 땅이 채운다.
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        return min(size.width / stage.width, size.height / stage.height, maxScale)
    }

    /// 무대는 가로 가운데, 세로 바닥에 붙인다(인물이 땅 위에 서 있도록).
    static func stageOrigin(for size: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(x: (size.width - stage.width * scale) / 2, y: size.height - stage.height * scale)
    }

    private static func image(_ name: String) -> some View {
        Image(name, bundle: .module).resizable()
    }
}

#if DEBUG
    // swiftlint:disable no_fixed_height - 미리보기에서 화면 비율별 모양을 보려고 크기를 고정한다
    #Preview("히어로 — iPhone 비율") { LoginHeroIllustration().frame(width: 393, height: 470) }
    #Preview("히어로 — 낮은 화면") { LoginHeroIllustration().frame(width: 375, height: 300) }
    #Preview("히어로 — 넓은 화면") { LoginHeroIllustration().frame(width: 820, height: 500) }
    // swiftlint:enable no_fixed_height
#endif
