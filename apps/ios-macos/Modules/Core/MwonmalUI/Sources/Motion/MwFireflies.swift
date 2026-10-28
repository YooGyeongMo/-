import SwiftUI

/// 반딧불(레퍼런스 V3): 빛나는 작은 점이 천천히 떠돌고 깜빡인다. 장식이라 VoiceOver·터치에서 빠진다.
///
/// 비용을 정해 둔다(ADR-0024): 점은 12개까지, 초당 30번 그리고, 동작 줄이기·화면 밖이면 그리지 않는다.
/// 점의 자리·속도는 번호로 정해지는 값이라(난수 없음) 매번 같은 그림이 나오고 테스트할 수 있다.
public struct MwFireflies: View {
    let count: Int
    let color: Color
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let maxCount = 12

    public init(count: Int = 9, color: Color = Color(red: 1, green: 0.93, blue: 0.7), isActive: Bool = true) {
        self.count = min(max(count, 0), Self.maxCount)
        self.color = color
        self.isActive = isActive
    }

    public var body: some View {
        if isActive, !reduceMotion, count >= 1 {
            TimelineView(.animation(minimumInterval: MwMotion.ambientFrameInterval)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    for index in 0 ..< count {
                        let fly = Firefly(index: index)
                        let point = fly.position(at: time, in: size)
                        let glow = fly.glow(at: time)
                        let radius = fly.radius
                        let halo = CGRect(x: point.x - radius * 4, y: point.y - radius * 4, width: radius * 8, height: radius * 8)
                        canvas.fill(
                            Path(ellipseIn: halo),
                            with: .radialGradient(
                                Gradient(colors: [color.opacity(0.55 * glow), color.opacity(0)]),
                                center: point, startRadius: 0, endRadius: radius * 4
                            )
                        )
                        let core = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                        canvas.fill(Path(ellipseIn: core), with: .color(color.opacity(0.9 * glow)))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 반딧불 하나. 번호만으로 자리·궤도·깜빡임이 정해진다.
struct Firefly {
    let index: Int

    /// 0~1 사이의 고정 값(번호마다 다르게). 황금비 수열이라 고르게 흩어진다.
    func unit(_ salt: Double) -> Double {
        let value = (Double(index) + 1) * 0.618_033_988_75 + salt * 0.414_213_562
        return value - value.rounded(.down)
    }

    var radius: CGFloat {
        1.6 + CGFloat(unit(1)) * 1.4
    }

    /// 화면 안 기준점(가장자리 8%는 비운다) + 작은 원 궤도.
    func position(at time: Double, in size: CGSize) -> CGPoint {
        let base = CGPoint(x: (0.08 + unit(2) * 0.84) * size.width, y: (0.08 + unit(3) * 0.62) * size.height)
        let period = 6 + unit(4) * 6
        let angle = (time / period + unit(5)) * 2 * .pi
        let orbit = 8 + unit(6) * 14
        return CGPoint(x: base.x + cos(angle) * orbit, y: base.y + sin(angle * 0.7) * orbit * 0.6)
    }

    /// 0.25~1 사이로 숨 쉬듯 밝아졌다 어두워진다.
    func glow(at time: Double) -> Double {
        let period = 2.5 + unit(7) * 3
        return 0.25 + 0.75 * (0.5 + 0.5 * sin((time / period + unit(8)) * 2 * .pi))
    }
}
