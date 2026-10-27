import SwiftUI

/// 떠 있는 아래 탭 바(Figma 51:1457): 353×64, 모서리 32, 흐림 24 + 흰 62%, 테두리 흰 90%, 그림자 0 12 32 16%.
/// 항목은 같은 너비, 고른 항목은 흰 85% 알약(높이 52, 모서리 26). 아이콘 아래 3pt에 11 SemiBold 이름.
public struct MwTabBar<Tab: Hashable>: View {
    public struct Item: Identifiable {
        public let tab: Tab
        public let icon: MwIcon
        public let title: Text
        public let badge: Int?

        public var id: Tab {
            tab
        }

        public init(tab: Tab, icon: MwIcon, title: Text, badge: Int? = nil) {
            self.tab = tab
            self.icon = icon
            self.title = title
            self.badge = badge
        }
    }

    let items: [Item]
    @Binding var selection: Tab
    @Environment(\.mwScale) private var s
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(items: [Item], selection: Binding<Tab>) {
        self.items = items
        _selection = selection
    }

    /// 화면 아래에서 탭 바 위 끝까지(Figma: 852 − 762 = 90). 내용이 가려지지 않게 이만큼 비워 둔다.
    public static var reservedHeight: CGFloat {
        104
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, 6 * s)
        .frame(height: 64 * s)
        .background {
            let shape = RoundedRectangle(cornerRadius: 32 * s, style: .circular)
            ZStack {
                if reduceTransparency {
                    shape.fill(MwColor.surface)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(MwColor.glassFillThin)
                }
                shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            }
            .mwGlassShadow(s, y: 12, blur: 32, opacity: 0.16)
        }
        .frame(width: 353 * s)
    }

    private func tabButton(_ item: Item) -> some View {
        let selected = item.tab == selection
        let color = selected ? MwColor.accentFill : MwColor.textDisabled
        return Button {
            selection = item.tab
        } label: {
            VStack(spacing: 3 * s) {
                MwIconView(item.icon, color: color)
                item.title
                    .font(MwFont.pretendard(.semiBold, size: 11 * s))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52 * s)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 26 * s, style: .circular).fill(MwColor.tabSelected)
                }
            }
            .overlay(alignment: .topLeading) {
                if let badge = item.badge, badge > 0 {
                    Text(verbatim: "\(min(badge, 99))")
                        .font(MwFont.pretendard(.bold, size: 11 * s))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5 * s)
                        .frame(minWidth: 18 * s, minHeight: 18 * s)
                        .background(Capsule().fill(MwColor.badgeFill))
                        .offset(x: 49.38 * s, y: 3 * s)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("tab.\(item.tab)")
    }
}
