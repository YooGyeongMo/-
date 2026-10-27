import Domain
import Foundation
import MwonmalUI
import SwiftUI

// MARK: - 판교 등급(5단계, contracts/db.dbml levels · packages/test-vectors/level_table.json)

public struct PangyoLevel: Equatable, Sendable {
    public let number: Int
    public let code: String
    public let nameKey: String
    public let minScore: Int
    public let maxScore: Int

    public static let all: [PangyoLevel] = [
        PangyoLevel(number: 1, code: "OUTSIDER", nameKey: "level.outsider", minScore: 0, maxScore: 19),
        PangyoLevel(number: 2, code: "TOURIST", nameKey: "level.tourist", minScore: 20, maxScore: 39),
        PangyoLevel(number: 3, code: "SETTLER", nameKey: "level.settler", minScore: 40, maxScore: 64),
        PangyoLevel(number: 4, code: "NATIVE", nameKey: "level.native", minScore: 65, maxScore: 84),
        PangyoLevel(number: 5, code: "LOCAL", nameKey: "level.local", minScore: 85, maxScore: 100),
    ]

    /// 서버 등급 코드 → 등급. 진단 전(nil)이면 점수로 정한다.
    public static func of(code: String?, score: Int) -> PangyoLevel {
        if let code, let level = all.first(where: { $0.code == code }) {
            return level
        }
        return all.last(where: { score >= $0.minScore }) ?? all[0]
    }

    /// 다음 등급까지 진행률(0~1). 마지막 등급이면 1.
    public func progress(score: Int) -> Double {
        guard number < Self.all.count else { return 1 }
        let span = Double(maxScore - minScore + 1)
        return min(max(Double(score - minScore) / span, 0), 1)
    }

    public var next: PangyoLevel? {
        number < Self.all.count ? Self.all[number] : nil
    }
}

/// 할 일 한 줄(Figma 51:1361): 체크 26 · 제목 17 Medium · 출처 칩 + 시각 · 오른쪽 기한 알약.
struct ActionRow: View {
    let item: UpcomingAction
    let onToggle: () -> Void
    @Environment(\.mwScale) private var scale

    var body: some View {
        HStack(spacing: 14 * scale) {
            Button(action: onToggle) {
                MwCheckbox(isOn: item.action.isChecked)
            }
            .buttonStyle(.plain)
            .frame(width: 26 * scale, height: 56 * scale)
            .contentShape(Rectangle().inset(by: -9 * scale))
            .accessibilityLabel(Text(verbatim: item.action.text))
            .accessibilityValue(Text(item.action.isChecked ? "home.actions.done" : "home.actions.notDone", bundle: .module))
            .accessibilityAddTraits(.isToggle)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.action.text)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(item.action.isChecked ? MwColor.textDisabled : MwColor.textPrimary)
                    .strikethrough(item.action.isChecked, color: MwColor.textDisabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6 * scale) {
                    MwSourceChip(
                        icon: item.meetingTitle == nil ? .clip : .meeting,
                        Text(verbatim: item.meetingTitle ?? String(localized: "home.actions.source.message", bundle: .module))
                    )
                    Text(verbatim: item.createdAt.mwClock)
                        .mwFont(.regular, 14, lineHeight: 20)
                        .foregroundStyle(MwColor.textSecondary)
                }
                .padding(.top, 1 * scale)
            }
            .padding(.vertical, 13 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if !item.action.isChecked, let due = DueBadge(dueAt: item.action.dueAt) {
                MwStatusPill(Text(due.key, bundle: .module), tone: due.tone)
            }
        }
        .padding(.horizontal, 18 * scale)
        .frame(minHeight: 56 * scale)
    }
}

/// 기한 → 알약(지남·오늘·내일).
struct DueBadge {
    let key: LocalizedStringKey
    let tone: MwStatusPill.Tone

    init?(dueAt: Date?, now: Date = Date(), calendar: Calendar = .current) {
        guard let dueAt else { return nil }
        if dueAt < now {
            key = "home.due.overdue"
            tone = .urgent
        } else if calendar.isDateInToday(dueAt) {
            key = "home.due.today"
            tone = .urgent
        } else if calendar.isDateInTomorrow(dueAt) {
            key = "home.due.tomorrow"
            tone = .soon
        } else {
            return nil
        }
    }
}
