import Foundation
import SwiftUI

/// 원문 형광펜(Figma 51:2223: #F7C948 50%, 15 Regular, 줄 높이 22). 누르면 그 용어의 뜻을 연다(#13).
///
/// SDK는 Domain을 모른다 → 표시 모델(`Highlight`)만 받는다(12번 D-21).
/// 위치는 유니코드 스칼라(서버·공용 벡터와 같은 단위). 범위가 원문을 벗어나거나 겹치면 그 칸은 그리지 않는다.
public struct JargonText: View {
    public struct Highlight: Hashable, Sendable {
        public let start: Int
        public let end: Int
        /// 누르면 열 용어 id. 사전에 없는 새 말이면 nil(누를 수 없다).
        public let termId: Int64?
        /// VoiceOver가 읽을 뜻("얼라인, 방향 맞추기").
        public let meaning: String

        public init(start: Int, end: Int, termId: Int64?, meaning: String) {
            self.start = start
            self.end = end
            self.termId = termId
            self.meaning = meaning
        }
    }

    public static let scheme = "mw-term"

    let text: String
    let highlights: [Highlight]
    let onTerm: (Int64) -> Void

    public init(_ text: String, highlights: [Highlight], onTerm: @escaping (Int64) -> Void = { _ in }) {
        self.text = text
        self.highlights = highlights
        self.onTerm = onTerm
    }

    public var body: some View {
        Text(Self.attributed(text, highlights))
            .mwFont(.regular, 15, lineHeight: 22)
            .foregroundStyle(MwColor.textPrimary)
            .tint(MwColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.scheme, let id = Int64(url.host() ?? "") else { return .systemAction }
                onTerm(id)
                return .handled
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityHint(Text(verbatim: highlights.map(\.meaning).joined(separator: ", ")))
            .accessibilityActions {
                ForEach(highlights.filter { $0.termId != nil }, id: \.self) { item in
                    Button(item.meaning) {
                        if let id = item.termId {
                            onTerm(id)
                        }
                    }
                }
            }
    }

    /// 스칼라 위치 → 형광펜 + 링크를 입힌 문자열. 순수 함수(테스트용).
    public static func attributed(_ text: String, _ highlights: [Highlight]) -> AttributedString {
        var result = AttributedString(text)
        let scalars = text.unicodeScalars
        let count = scalars.count
        var lastEnd = 0
        for item in highlights.sorted(by: { $0.start < $1.start }) {
            guard item.start >= lastEnd, item.start < item.end, item.end <= count else { continue }
            let lower = scalars.index(scalars.startIndex, offsetBy: item.start)
            let upper = scalars.index(scalars.startIndex, offsetBy: item.end)
            guard let range = Range(lower ..< upper, in: result) else { continue }
            result[range].backgroundColor = MwColor.jargonHighlight
            if let id = item.termId {
                result[range].link = URL(string: "\(scheme)://\(id)")
            }
            lastEnd = item.end
        }
        return result
    }
}
