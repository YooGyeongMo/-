import Domain
import Foundation
import MwonmalUI
import SwiftUI

/// 할 일 한 줄(A-06 51:2304): 체크 · 17 Medium · 아래 기한 문구 · 오른쪽 오늘/내일 알약.
struct ActionLine: View {
    let action: ActionItem
    let onToggle: () -> Void
    @Environment(\.mwScale) private var scale

    var body: some View {
        HStack(spacing: 14 * scale) {
            Button(action: onToggle) { MwCheckbox(isOn: action.isChecked) }
                .buttonStyle(.plain)
                .frame(width: 26 * scale, height: 56 * scale)
                .contentShape(Rectangle().inset(by: -9 * scale))
                .accessibilityLabel(Text(verbatim: action.text))
                .accessibilityValue(Text(action.isChecked ? "translate.action.done" : "translate.action.notDone", bundle: .module))
                .accessibilityAddTraits(.isToggle)
                .accessibilityIdentifier("action.check.\(action.id)")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: action.text)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(action.isChecked ? MwColor.textDisabled : MwColor.textPrimary)
                    .strikethrough(action.isChecked, color: MwColor.textDisabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = DueText.detail(action) {
                    Text(verbatim: detail)
                        .mwFont(.regular, 14, lineHeight: 20)
                        .foregroundStyle(MwColor.textSecondary)
                        .padding(.top, 1 * scale)
                }
            }
            .padding(.vertical, 13 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !action.isChecked, let pill = DueText.pill(action.dueAt) {
                MwStatusPill(Text(pill.key, bundle: .module), tone: pill.tone)
            }
        }
        .padding(.horizontal, 18 * scale)
        .frame(minHeight: 56 * scale)
    }
}

/// 기한 문구: "오늘 17:30 · 17:00 알림"(마감 30분 전 알림), 시각이 없으면 원문 힌트.
enum DueText {
    static let alertLead: TimeInterval = 30 * 60

    static func detail(_ action: ActionItem, calendar: Calendar = .current) -> String? {
        guard let due = action.dueAt else { return action.dueHint }
        let day: String = if calendar.isDateInToday(due) {
            String(localized: "translate.due.today", bundle: .module)
        } else if calendar.isDateInTomorrow(due) {
            String(localized: "translate.due.tomorrow", bundle: .module)
        } else {
            fmt(
                "translate.card.date",
                Calendar.current.component(.month, from: due),
                Calendar.current.component(.day, from: due),
                due.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
            )
        }
        let time = due.mwClock
        guard action.alertEnabled else { return "\(day) \(time)" }
        let alert = due.addingTimeInterval(-alertLead).mwClock
        return fmt("translate.due.withAlert", day, time, alert)
    }

    static func pill(
        _ due: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (key: LocalizedStringKey, tone: MwStatusPill.Tone)? {
        guard let due else { return nil }
        if due < now {
            return ("translate.due.overdue", .urgent)
        }
        if calendar.isDateInToday(due) {
            return ("translate.due.today", .urgent)
        }
        if calendar.isDateInTomorrow(due) {
            return ("translate.due.tomorrow", .soon)
        }
        return nil
    }
}
