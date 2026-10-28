import SwiftUI

/// 온보딩 그림 무대의 배치 정보. 그림 위에 글자 카드(알림·칩)를 얹는 쪽이 Figma 좌표를 화면 좌표로 바꿀 때 쓴다.
public struct MwStageGeometry: Equatable, Sendable {
    /// 무대(393×500)의 화면 속 왼쪽 위.
    public let origin: CGPoint
    /// Figma pt → 화면 pt.
    public let scale: CGFloat

    /// Figma 무대 좌표의 사각형 → 화면 좌표.
    public func rect(_ figma: CGRect) -> CGRect {
        CGRect(x: origin.x + figma.minX * scale, y: origin.y + figma.minY * scale, width: figma.width * scale, height: figma.height * scale)
    }
}

/// 온보딩 O-1~O-3 그림(Figma 51:27·51:187·51:310). S-01 히어로처럼 레이어로 나눠 그린다.
///
/// - 하늘: 단색(O-3은 그라데이션 그림). 화면 끝까지 채운다.
/// - 땅(물결): 가로로만 늘린다. 어떤 너비에서도 양끝에 닿는다.
/// - 무대(사람·책상·해·나무)와 칩·말풍선: 393×500 무대 안에서 비율을 지킨 채 함께 커지고 작아진다(가운데·바닥 정렬).
///
/// 레이어마다 따로 움직인다(ADR-0024): `isActive`가 켜지면 칩·말풍선이 차례로 튀어나와 떠다니고,
/// O-3 자전거는 왼쪽에서 들어와 페달을 밟는다. 움직임이 끝나면 모든 레이어가 Figma 자리에 있다.
/// 무대 크기와 같은 PDF를 겹치는 방식이라 레이어 위치는 Figma와 픽셀 단위로 같다(합성 비교 차이 0).
public struct OnboardingIllustration<Overlay: View>: View {
    let page: Int
    let isActive: Bool
    let overlay: (MwStageGeometry) -> Overlay

    public init(page: Int, isActive: Bool, @ViewBuilder overlay: @escaping (MwStageGeometry) -> Overlay) {
        self.page = page
        self.isActive = isActive
        self.overlay = overlay
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = OnboardingStage.scale(for: size)
            let origin = OnboardingStage.origin(for: size, scale: scale)
            let geometry = MwStageGeometry(origin: origin, scale: scale)
            ZStack(alignment: .topLeading) {
                scene(size: size, geometry: geometry)
                    .accessibilityHidden(true)
                overlay(geometry)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .clipped()
    }

    @ViewBuilder private func scene(size: CGSize, geometry: MwStageGeometry) -> some View {
        let spec = OnboardingStage.pages[min(max(page, 0), OnboardingStage.pages.count - 1)]
        ZStack(alignment: .topLeading) {
            switch spec.sky {
            case let .color(name):
                Color(name, bundle: .module)
            case let .image(name):
                // 그라데이션은 무대 바닥까지 늘린다(위로 남는 칸도 같은 색 흐름으로 채움).
                Self.image(name).frame(width: size.width, height: geometry.origin.y + OnboardingStage.size.height * geometry.scale)
            }
            ForEach(spec.layers, id: \.name) { layer in
                layerView(layer, size: size, geometry: geometry)
            }
            if spec.fireflies {
                MwFireflies(count: 10, isActive: isActive)
                    .frame(width: size.width, height: geometry.origin.y + 300 * geometry.scale)
            }
        }
    }

    @ViewBuilder private func layerView(_ layer: OnboardingStage.Layer, size: CGSize, geometry: MwStageGeometry) -> some View {
        let scale = geometry.scale
        switch layer.kind {
        case let .ground(frame):
            // 가로로 늘어나는 땅: 양옆으로 frame.minX(음수)만큼 넘친다.
            Self.image(layer.name)
                .frame(width: size.width + (frame.width - OnboardingStage.size.width) * scale, height: frame.height * scale)
                .offset(x: frame.minX * scale, y: geometry.origin.y + frame.minY * scale)
        case .stage:
            stageImage(layer.name, geometry: geometry)
        case let .pop(anchor, order, tilt, float):
            let drift = OnboardingStage.drift(order: order)
            stageImage(layer.name, geometry: geometry)
                .mwPop(isActive, index: order, tilt: tilt, baseDelay: 0.25, anchor: anchor)
                .mwFloat(isActive, amplitude: float * scale, period: drift.period, phase: drift.phase)
        case .rider:
            stageImage(layer.name, geometry: geometry)
                .mwSlideIn(isActive, from: CGSize(width: -150 * scale, height: 0), delay: 0.2)
                .mwFloat(isActive, amplitude: 1.5 * scale, period: 0.7, phase: 0.8)
        }
    }

    private func stageImage(_ name: String, geometry: MwStageGeometry) -> some View {
        Self.image(name)
            .frame(width: OnboardingStage.size.width * geometry.scale, height: OnboardingStage.size.height * geometry.scale)
            .offset(x: geometry.origin.x, y: geometry.origin.y)
    }

    private static func image(_ name: String) -> some View {
        Image(name, bundle: .module).resizable()
    }
}

/// 무대 수치(Figma 좌표). 레이어 위치는 내보낸 PDF를 Figma 2배 렌더와 겹쳐 확인했다.
public enum OnboardingStage {
    public static let size = CGSize(width: 393, height: 500)
    /// iPad·Mac에서 사람이 지나치게 커지지 않게 막는 상한.
    static let maxScale: CGFloat = 1.6
    public static let pageCount = 3

    enum Sky {
        case color(String)
        case image(String)
    }

    enum Kind {
        /// 가로로 늘어나는 땅(Figma 사각형: x는 -20 등 넘침 포함).
        case ground(CGRect)
        /// 무대 크기 그대로(393×500 PDF).
        case stage
        /// 튀어나와 떠다니는 칩: 기준점(칩 가운데), 순서, 처음 기울기, 떠다니는 높이.
        case pop(anchor: UnitPoint, order: Int, tilt: Double, float: CGFloat)
        /// O-3 자전거.
        case rider
    }

    struct Layer {
        let name: String
        let kind: Kind
    }

    struct Page {
        let sky: Sky
        let layers: [Layer]
        var fireflies = false
    }

    /// 칩 기준점: Figma 칩 사각형 가운데 / 무대 크기.
    static func anchor(_ rect: CGRect) -> UnitPoint {
        UnitPoint(x: rect.midX / size.width, y: rect.midY / size.height)
    }

    static let pages: [Page] = [
        // O-1(51:27): 노란 하늘 · 파란 물결 · 회의실 · 판교어 칩 5개 · 물음표 3개
        Page(sky: .color("Onboarding1Sky"), layers: [
            Layer(name: "Onboarding1Ground", kind: .ground(CGRect(x: -20, y: 315.7, width: 433, height: 204.3))),
            Layer(name: "Onboarding1Stage", kind: .stage),
            Layer(
                name: "Onboarding1ChipNext",
                kind: .pop(anchor: anchor(CGRect(x: 119, y: 85, width: 65, height: 34)), order: 0, tilt: -10, float: 4)
            ),
            Layer(
                name: "Onboarding1ChipASAP",
                kind: .pop(anchor: anchor(CGRect(x: 174, y: 130, width: 81, height: 35)), order: 1, tilt: 8, float: 5)
            ),
            Layer(
                name: "Onboarding1ChipScope",
                kind: .pop(anchor: anchor(CGRect(x: 23, y: 155, width: 114, height: 36)), order: 2, tilt: -8, float: 4)
            ),
            Layer(
                name: "Onboarding1ChipRR",
                kind: .pop(anchor: anchor(CGRect(x: 152, y: 193, width: 70, height: 36)), order: 3, tilt: 10, float: 5)
            ),
            Layer(
                name: "Onboarding1ChipAlign",
                kind: .pop(anchor: anchor(CGRect(x: 46, y: 225, width: 70, height: 36)), order: 4, tilt: -6, float: 4)
            ),
            Layer(
                name: "Onboarding1QuestionBig",
                kind: .pop(anchor: anchor(CGRect(x: 276, y: 158, width: 63, height: 108)), order: 6, tilt: 14, float: 6)
            ),
            Layer(
                name: "Onboarding1QuestionMid",
                kind: .pop(anchor: anchor(CGRect(x: 212, y: 225, width: 24, height: 41)), order: 7, tilt: -12, float: 5)
            ),
            Layer(
                name: "Onboarding1QuestionSmall",
                kind: .pop(anchor: anchor(CGRect(x: 337, y: 230, width: 22, height: 39)), order: 8, tilt: 12, float: 5)
            ),
        ]),
        // O-2(51:187): 청록 하늘 · 노을 물결 · 모니터 앞 사람 · 판교어 말풍선 → 쉬운 말 말풍선
        Page(sky: .color("Onboarding2Sky"), layers: [
            Layer(name: "Onboarding2Ground", kind: .ground(CGRect(x: -20, y: 351, width: 433, height: 169))),
            Layer(name: "Onboarding2Stage", kind: .stage),
            Layer(
                name: "Onboarding2BubbleJargon",
                kind: .pop(anchor: anchor(CGRect(x: 16, y: 75, width: 196, height: 102)), order: 0, tilt: -6, float: 3)
            ),
            // 쉬운 말은 판교어가 자리 잡은 뒤에 "풀려서" 나온다.
            Layer(
                name: "Onboarding2BubblePlain",
                kind: .pop(anchor: anchor(CGRect(x: 168, y: 118, width: 204, height: 102)), order: 6, tilt: 5, float: 3)
            ),
        ]),
        // O-3(51:310): 노을 하늘 · 언덕 · 누워 쉬는 사람 · 길 · 자전거 퇴근 · 반딧불
        Page(sky: .image("Onboarding3Sky"), layers: [
            Layer(name: "Onboarding3GroundBack", kind: .ground(CGRect(x: -20, y: 243, width: 433, height: 277))),
            Layer(name: "Onboarding3StageBack", kind: .stage),
            // 길(51:340)은 선 두께 때문에 PDF가 양옆으로 6pt씩 더 넓다(440 → 452).
            Layer(name: "Onboarding3GroundMid", kind: .ground(CGRect(x: -26, y: 327.3, width: 452.002, height: 192.7))),
            Layer(name: "Onboarding3Rider", kind: .rider),
            Layer(name: "Onboarding3GroundFront", kind: .ground(CGRect(x: -20, y: 377.5, width: 433, height: 142.5))),
        ], fireflies: true),
    ]

    /// 칩마다 떠다니는 주기·시작을 조금씩 다르게(같이 움직이면 기계 같다). 튀어나온 뒤(0.9초~)부터 떠다닌다.
    static func drift(order: Int) -> (period: Double, phase: Double) {
        (3 + Double(order % 3) * 0.6, 0.9 + Double(order) * 0.17)
    }

    /// 너비와 높이 중 빡빡한 쪽에 맞춘다. 남는 쪽은 하늘과 땅이 채운다.
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        return min(size.width / Self.size.width, size.height / Self.size.height, maxScale)
    }

    /// 무대는 가로 가운데, 세로 바닥에 붙인다.
    static func origin(for size: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(x: (size.width - Self.size.width * scale) / 2, y: size.height - Self.size.height * scale)
    }
}
