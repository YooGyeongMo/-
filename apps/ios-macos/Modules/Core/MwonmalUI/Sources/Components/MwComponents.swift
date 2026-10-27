import SwiftUI

// Figma v5.2 화면에서 되풀이되는 조각들. 모든 수치는 Figma pt이고 `mwScale`을 곱해 그린다.
// 그림자는 CSS box-shadow(blur)를 SwiftUI radius(≈ blur/2)로 옮겼다.

/// Figma 아이콘(SF Symbols에서 뽑은 벡터, Icons.xcassets). 단색 아이콘은 템플릿이라 색은 부르는 쪽이 정한다.
public enum MwIcon: String, CaseIterable, Sendable {
    case bike, bikeLarge, cards, cardsSmall, check, checkCircle, checklist, chevronDown, chevronRight, clip, close
    case flame, gear, layers, layersFill, layersOutline, lock, meeting, nuance, plus, sparkles, sparkleSmall
    case tabHome, tabMy, tabProject, tabReview, waveform, back, ellipsis

    public var image: Image {
        Image("icon.\(rawValue)", bundle: .module)
    }

    /// Figma 아이콘 상자 크기(pt).
    public var size: CGSize {
        switch self {
        case .bike: CGSize(width: 21.391, height: 13.391)
        case .bikeLarge: CGSize(width: 27.969, height: 17.516)
        case .cards: CGSize(width: 17.656, height: 19.125)
        case .cardsSmall: CGSize(width: 13.297, height: 14.047)
        case .check: CGSize(width: 11.422, height: 11.125)
        case .checkCircle: CGSize(width: 15.922, height: 15.922)
        case .checklist: CGSize(width: 14.234, height: 12.813)
        case .chevronDown: CGSize(width: 8.766, height: 5.109)
        case .chevronRight: CGSize(width: 6.641, height: 11.391)
        case .clip: CGSize(width: 11.984, height: 14.734)
        case .close: CGSize(width: 13.531, height: 13.5)
        case .flame: CGSize(width: 16.891, height: 20) // 그림자 여백 포함(아이콘 10.891×14)
        case .gear: CGSize(width: 17.844, height: 17.844)
        case .layers: CGSize(width: 13.25, height: 14.563)
        case .layersFill: CGSize(width: 16.313, height: 17.922)
        case .layersOutline: CGSize(width: 17.328, height: 19.047)
        case .lock: CGSize(width: 8.656, height: 12.453)
        case .meeting: CGSize(width: 22.078, height: 10.531)
        case .nuance: CGSize(width: 13.281, height: 12.516)
        case .plus: CGSize(width: 13.203, height: 13.203)
        case .sparkles: CGSize(width: 14.844, height: 18.063)
        case .sparkleSmall: CGSize(width: 11.734, height: 14.469)
        case .tabHome: CGSize(width: 25.641, height: 22.594)
        case .tabMy: CGSize(width: 21.906, height: 21.906)
        case .tabProject: CGSize(width: 21.969, height: 23.844)
        case .tabReview: CGSize(width: 22.5, height: 23.781)
        case .waveform: CGSize(width: 10.406, height: 11.609)
        case .back: CGSize(width: 8.672, height: 14.906)
        case .ellipsis: CGSize(width: 15.969, height: 3.516)
        }
    }
}

/// Figma 크기 그대로(× 배율) 그리는 아이콘.
public struct MwIconView: View {
    let icon: MwIcon
    let color: Color?
    @Environment(\.mwScale) private var s
    @ScaledMetric(relativeTo: .body) private var t: CGFloat = 1

    public init(_ icon: MwIcon, color: Color? = nil) {
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        let k = s * min(t, 1.6)
        Group {
            if let color {
                icon.image.resizable().foregroundStyle(color)
            } else {
                icon.image.resizable()
            }
        }
        .frame(width: icon.size.width * k, height: icon.size.height * k)
        .accessibilityHidden(true)
    }
}

// MARK: - 카드·그림자

public extension View {
    /// 흰 카드(Figma: 0 1 0 rgba(90,60,30,.04), 0 2 6 rgba(90,60,30,.06)).
    func mwCardShadow(_ s: CGFloat) -> some View {
        shadow(color: Color(red: 90 / 255, green: 60 / 255, blue: 30 / 255).opacity(0.04), radius: 0, y: 1 * s)
            .shadow(color: Color(red: 90 / 255, green: 60 / 255, blue: 30 / 255).opacity(0.06), radius: 3 * s, y: 2 * s)
    }

    /// 떠 있는 카드(Figma drop-shadow: 0 1 0 rgba(90,60,30,.05), 0 6 8 rgba(90,60,30,.09)).
    func mwRaisedShadow(_ s: CGFloat) -> some View {
        shadow(color: Color(red: 90 / 255, green: 60 / 255, blue: 30 / 255).opacity(0.05), radius: 0, y: 1 * s)
            .shadow(color: Color(red: 90 / 255, green: 60 / 255, blue: 30 / 255).opacity(0.09), radius: 4 * s, y: 6 * s)
    }

    /// 유리 패널 그림자(Figma: 0 10 30 rgba(60,50,20,.14)).
    func mwGlassShadow(_ s: CGFloat, y: CGFloat = 10, blur: CGFloat = 30, opacity: Double = 0.14) -> some View {
        shadow(color: Color(red: 60 / 255, green: 50 / 255, blue: 20 / 255).opacity(opacity), radius: blur / 2 * s, y: y * s)
    }
}

/// 유리 면(배경 흐림 + 흰 반투명 + 흰 테두리 + 위쪽 안쪽 빛). Figma 51:1329·51:1434·51:2936.
public struct MwGlassBackground: View {
    let cornerRadius: CGFloat
    let fill: Color
    @Environment(\.mwScale) private var s
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat, fill: Color = MwColor.glassFill) {
        self.cornerRadius = cornerRadius
        self.fill = fill
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius * s, style: .circular)
        ZStack {
            if reduceTransparency {
                shape.fill(MwColor.surface)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(fill)
            }
            shape.strokeBorder(MwColor.glassBorder, lineWidth: 1)
            // inset 0 1 0 rgba(255,255,255,.85): 위쪽 1pt 빛
            shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                .mask(alignment: .top) { Rectangle().frame(height: 1.5 * s) }
        }
    }
}

/// 둥근 유리 버튼(44×44, Figma 51:2936 설정·51:3513 뒤로).
public struct MwGlassCircleButton: View {
    let icon: MwIcon
    let diameter: CGFloat
    let label: LocalizedStringKey
    let bundle: Bundle?
    let action: () -> Void
    @Environment(\.mwScale) private var s

    public init(_ icon: MwIcon, diameter: CGFloat = 44, label: LocalizedStringKey, bundle: Bundle? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.diameter = diameter
        self.label = label
        self.bundle = bundle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            MwIconView(icon, color: MwColor.textPrimary)
                .frame(width: diameter * s, height: diameter * s)
                .background(MwGlassBackground(cornerRadius: diameter / 2, fill: MwColor.glassFillThin))
                .mwGlassShadow(s, y: 4, blur: 14, opacity: 0.1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(Text(label, bundle: bundle))
    }
}

// MARK: - 버튼

/// 파란 주 버튼(Figma 51:1348·51:2363·51:3385): 바탕 #2F6FD6, 아래 2pt #2459B4, 0 8 18 파랑 28%.
public struct MwPrimaryButtonStyle: ButtonStyle {
    let height: CGFloat
    let radius: CGFloat
    @Environment(\.mwScale) private var s
    @Environment(\.isEnabled) private var isEnabled

    public init(height: CGFloat = 56, radius: CGFloat = 18) {
        self.height = height
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius * s, style: .circular)
        configuration.label
            .foregroundStyle(MwColor.accentOnFill)
            .frame(maxWidth: .infinity, minHeight: height * s)
            .background(shape.fill(MwColor.accentFill))
            .background(shape.fill(MwColor.accentShadow).offset(y: 2 * s))
            .shadow(color: Color(red: 47 / 255, green: 111 / 255, blue: 214 / 255).opacity(0.28), radius: 9 * s, y: 8 * s)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .offset(y: configuration.isPressed ? 1 * s : 0)
            .contentShape(shape)
    }
}

/// 흰 보조 버튼(Figma 51:3380 "판교어 해석").
public struct MwSecondaryButtonStyle: ButtonStyle {
    let height: CGFloat
    @Environment(\.mwScale) private var s

    public init(height: CGFloat = 48) {
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18 * s, style: .circular)
        configuration.label
            .foregroundStyle(MwColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: height * s)
            .background(shape.fill(MwColor.surface))
            .mwRaisedShadow(s)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(shape)
    }
}

// MARK: - 작은 조각

/// 할 일 체크 상자(26×26, 모서리 9, 테두리 2).
public struct MwCheckbox: View {
    let isOn: Bool
    @Environment(\.mwScale) private var s

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .circular)
        ZStack {
            shape.fill(isOn ? MwColor.accentFill : MwColor.surface)
            shape.strokeBorder(isOn ? MwColor.accentFill : MwColor.checkboxBorder, lineWidth: 2 * s)
            if isOn {
                MwIconView(.check, color: MwColor.accentOnFill)
            }
        }
        .frame(width: 26 * s, height: 26 * s)
    }
}

/// 상태 알약(26 높이, 모서리 9, 13 Bold). 오늘 = 빨강, 내일 = 주황, 지금 = 파랑.
public struct MwStatusPill: View {
    public enum Tone: Sendable {
        case urgent, soon, info, neutral
    }

    let text: Text
    let tone: Tone
    let height: CGFloat
    let size: CGFloat
    @Environment(\.mwScale) private var s

    public init(_ text: Text, tone: Tone, height: CGFloat = 26, size: CGFloat = 13) {
        self.text = text
        self.tone = tone
        self.height = height
        self.size = size
    }

    public var body: some View {
        text
            .mwFont(.bold, size)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10 * s)
            .frame(minHeight: height * s)
            .background(RoundedRectangle(cornerRadius: 9 * s, style: .circular).fill(background))
    }

    private var foreground: Color {
        switch tone {
        case .urgent: MwColor.urgentText
        case .soon: MwColor.soonText
        case .info: MwColor.accentFill
        case .neutral: MwColor.textStrong
        }
    }

    private var background: Color {
        switch tone {
        case .urgent: MwColor.urgentFill
        case .soon: MwColor.soonFill
        case .info: MwColor.accentSoftFill
        case .neutral: MwColor.chipFill
        }
    }
}

/// 출처 칩(22 높이, 모서리 7, 아이콘 + 12 Bold). Figma 51:1368 "스프린트 계획 회의"·51:1408 "슬랙".
public struct MwSourceChip: View {
    let icon: MwIcon?
    let text: Text
    let height: CGFloat
    let size: CGFloat
    @Environment(\.mwScale) private var s

    public init(icon: MwIcon?, _ text: Text, height: CGFloat = 22, size: CGFloat = 12) {
        self.icon = icon
        self.text = text
        self.height = height
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4 * s) {
            if let icon {
                MwIconView(icon, color: MwColor.textStrong)
            }
            text.mwFont(.bold, size).foregroundStyle(MwColor.textStrong).lineLimit(1)
        }
        .padding(.horizontal, 8 * s)
        .frame(minHeight: height * s)
        .background(RoundedRectangle(cornerRadius: 7 * s, style: .circular).fill(MwColor.chipFill))
    }
}

/// 섹션 머리(Figma 51:1354: 14 SemiBold 회색 + 오른쪽 13 SemiBold 파랑, px 4, pb 8).
public struct MwSectionHeader<Trailing: View>: View {
    let title: Text
    let trailing: Trailing
    @Environment(\.mwScale) private var s

    public init(_ title: Text, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack {
            title.mwFont(.semiBold, 14).foregroundStyle(MwColor.textSecondary).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8 * s)
            trailing
        }
        .padding(.horizontal, 4 * s)
        .padding(.bottom, 8 * s)
    }
}

public extension MwSectionHeader where Trailing == EmptyView {
    init(_ title: Text) {
        self.init(title) { EmptyView() }
    }
}

/// 흰 목록 카드(모서리 20) 안의 행들 사이 구분선(왼쪽 18 들여씀).
public struct MwRowDivider: View {
    @Environment(\.mwScale) private var s

    public init() {}

    public var body: some View {
        Rectangle().fill(MwColor.separator).frame(height: 1).padding(.leading, 18 * s)
    }
}

/// 시트 손잡이(40×5, Figma 51:2202).
public struct MwGrabber: View {
    @Environment(\.mwScale) private var s

    public init() {}

    public var body: some View {
        Capsule().fill(MwColor.sheetGrabber).frame(width: 40 * s, height: 5 * s).accessibilityHidden(true)
    }
}

/// 아래에서 잠깐 떴다 사라지는 안내(다음 업데이트 기능 등). VoiceOver에도 읽힌다.
public struct MwToast: View {
    let text: Text
    @Environment(\.mwScale) private var s

    public init(_ text: Text) {
        self.text = text
    }

    public var body: some View {
        text
            .mwFont(.semiBold, 14)
            .foregroundStyle(MwColor.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16 * s)
            .padding(.vertical, 12 * s)
            .background(MwGlassBackground(cornerRadius: 18))
            .mwGlassShadow(s)
            .padding(.horizontal, 20 * s)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// 칩 줄바꿈 배치(Figma 51:2334: 간격 6). 줄이 넘치면 다음 줄로.
public struct MwFlowLayout: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = Self.rows(width: width, sizes: subviews.map { $0.sizeThatFits(.unspecified) }, spacing: spacing)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in Self.rows(width: bounds.width, sizes: sizes, spacing: spacing) {
            var x = bounds.minX
            for index in row.indices {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += row.height + spacing
        }
    }

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    static func rows(width: CGFloat, sizes: [CGSize], spacing: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, size) in sizes.enumerated() {
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
