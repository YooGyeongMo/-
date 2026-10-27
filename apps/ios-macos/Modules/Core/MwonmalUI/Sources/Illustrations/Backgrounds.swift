import SwiftUI

/// 배경 장면(Figma 51:2733 MY = 노을, 51:3358 프로젝트 = 하늘).
///
/// 393×852 한 장을 늘리지 않고 나눠 그린다: 세로 그라데이션(화면 전체) + 오른쪽 위 원(위에 붙음) + 아래 물결 3겹
/// (아래에 붙음, 좌우 20씩 넘침). 그래서 SE처럼 낮은 화면에서도 원과 물결의 모양이 그대로다.
public struct MwSceneBackground: View {
    public enum Palette: Sendable {
        case sunset, sky

        var top: Color {
            switch self {
            case .sunset: Color(sceneHex: 0xFBD9C4)
            case .sky: Color(sceneHex: 0xCFE6F7)
            }
        }

        var circle: Color {
            switch self {
            case .sunset: Color(sceneHex: 0xF7C3A6)
            case .sky: Color(sceneHex: 0xB5D9F2)
            }
        }

        var waves: [(Color, Double)] {
            switch self {
            case .sunset: [(Color(sceneHex: 0xFBE6E2), 1), (Color(sceneHex: 0xF5C9A8), 0.9), (Color(sceneHex: 0xEE9A78), 0.7)]
            case .sky: [(Color(sceneHex: 0xE2F3F2), 1), (Color(sceneHex: 0xA9DAD6), 0.9), (Color(sceneHex: 0x5DB5B1), 0.7)]
            }
        }
    }

    let palette: Palette
    @Environment(\.mwScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    public init(_ palette: Palette) {
        self.palette = palette
    }

    /// 물결 3겹: (이름, 높이, 화면 아래에서 위 끝까지 거리 = 852 − Figma top).
    struct Wave {
        let name: String
        let height: CGFloat
        let top: CGFloat
    }

    static let waves: [Wave] = [
        Wave(name: "SceneWave1", height: 195, top: 852 - 677),
        Wave(name: "SceneWave2", height: 154.9, top: 852 - 717.1),
        Wave(name: "SceneWave3", height: 120.2, top: 852 - 751.8),
    ]

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    stops: [
                        .init(color: palette.top, location: 0),
                        .init(color: Color(sceneHex: 0xF8F0DE), location: 0.45),
                        .init(color: MwColor.canvas, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(colorScheme == .dark ? 0.18 : 1)
                // 원 108×108: 위 42(4.93%), 오른쪽 −13(−3.31%)
                Circle()
                    .fill(palette.circle.opacity(0.55))
                    .frame(width: 108 * scale, height: 108 * scale)
                    .offset(x: size.width - (108 - 13) * scale, y: 42 * scale)
                ForEach(Array(Self.waves.enumerated()), id: \.offset) { index, wave in
                    let (color, opacity) = palette.waves[index]
                    Image(wave.name, bundle: .module)
                        .resizable()
                        .foregroundStyle(color.opacity(opacity))
                        .frame(width: size.width + 40 * scale, height: wave.height * scale)
                        .offset(x: -20 * scale, y: size.height - wave.top * scale)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// 홈 히어로(Figma 51:1274, 393×300): 노란 하늘·해·물결·자전거 탄 사람·걷는 두 사람. 너비에 맞춰 같은 비율로.
public struct MwHomeHero: View {
    @Environment(\.mwScale) private var scale

    public init() {}

    public var body: some View {
        Image("HomeHero", bundle: .module)
            .resizable()
            .frame(width: 393 * scale, height: 300 * scale)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// MY 프로필 그림(Figma 51:2748, 64×64, 모서리 22).
public struct MwProfileAvatar: View {
    @Environment(\.mwScale) private var scale

    public init() {}

    public var body: some View {
        Image("ProfileAvatar", bundle: .module)
            .resizable()
            .frame(width: 64 * scale, height: 64 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 22 * scale, style: .circular))
            .accessibilityHidden(true)
    }
}

private extension Color {
    /// 장면 일러스트 전용 색(Figma 그림 값). 글자·버튼 색은 MwColor 토큰만 쓴다.
    init(sceneHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
