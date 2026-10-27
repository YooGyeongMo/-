import SwiftUI

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
