import Domain
import FeatureKit
import MwonmalUI
import Observation
import Routing
import SwiftUI

/// SettingsFeature 모듈(ADR-0016). 다른 Feature를 모르고, 이동은 `AppNavigating`으로만 요청한다.
/// 화면: A-09 MY(등급·설정 입구), 설정 시트(AI 외부 전송 옵트인 #25, 로그아웃, 정보).
public enum SettingsFeatureModule {
    public static let name = "SettingsFeature"
}

public struct SettingsDependencies: Sendable {
    public let repository: any TranslationRepository
    public let consent: any AIConsentStore

    public init(repository: any TranslationRepository, consent: any AIConsentStore) {
        self.repository = repository
        self.consent = consent
    }
}

@MainActor @Observable
public final class MyViewModel {
    public private(set) var translationCount: Int?
    public private(set) var projectCount: Int?
    private let repository: any TranslationRepository

    public init(repository: any TranslationRepository) {
        self.repository = repository
    }

    public func load() async {
        async let projects = repository.projects()
        if let page = try? await repository.translations(projectId: nil, page: 1, size: 1) {
            translationCount = page.totalElements
        }
        if let list = try? await projects {
            projectCount = list.count
        }
    }
}

/// 판교 등급 5단계(A-09 목록). 색은 Figma 등급 배지 값(그림 성격이라 토큰 밖).
struct LevelRowSpec {
    let number: Int
    let code: String
    let nameKey: LocalizedStringKey
    let rangeKey: LocalizedStringKey
    let badge: Color
    let minScore: Int

    /// 머리 줄에 쓰는 짧은 이름("관광객").
    var shortKey: LocalizedStringKey {
        let key = "my.level.\(number).short" // 보간이 형식 키가 되지 않게 문자열로 먼저 만든다
        return LocalizedStringKey(key)
    }

    static let all: [LevelRowSpec] = [
        LevelRowSpec(
            number: 1,
            code: "OUTSIDER",
            nameKey: "my.level.1.name",
            rangeKey: "my.level.1.range",
            badge: Color(levelHex: 0xC9D6E8),
            minScore: 0
        ),
        LevelRowSpec(
            number: 2,
            code: "TOURIST",
            nameKey: "my.level.2.name",
            rangeKey: "my.level.2.range",
            badge: Color(levelHex: 0x8CCBEA),
            minScore: 20
        ),
        LevelRowSpec(
            number: 3,
            code: "SETTLER",
            nameKey: "my.level.3.name",
            rangeKey: "my.level.3.range",
            badge: Color(levelHex: 0x5DB5B1),
            minScore: 40
        ),
        LevelRowSpec(
            number: 4,
            code: "NATIVE",
            nameKey: "my.level.4.name",
            rangeKey: "my.level.4.range",
            badge: Color(levelHex: 0x5DAE6B),
            minScore: 65
        ),
        LevelRowSpec(
            number: 5,
            code: "LOCAL",
            nameKey: "my.level.5.name",
            rangeKey: "my.level.5.range",
            badge: Color(levelHex: 0xF7C948),
            minScore: 85
        ),
    ]

    static func current(code: String?, score: Int) -> Int {
        if let code, let spec = all.first(where: { $0.code == code }) {
            return spec.number
        }
        return all.last(where: { score >= $0.minScore })?.number ?? 1
    }
}

/// A-09 MY(Figma 51:2731): 노을 배경, 오른쪽 위 설정(44 유리 원), 프로필 64 + 이름 22 + 직군·연속 + 숫자 줄,
/// 판교 등급 목록(지난 = 초록 ✓, 지금 = "지금", 잠긴 = 회색 + 자물쇠), 퇴근길 복습·프로젝트 행.
public struct MyRootView: View {
    @ViewModelState private var model: MyViewModel
    let user: UserProfile?
    let refreshKey: Int
    let onNotice: (LocalizedStringKey) -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var scale

    public init(
        dependencies: SettingsDependencies,
        user: UserProfile?,
        refreshKey: Int = 0,
        onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }
    ) {
        _model = ViewModelState(wrappedValue: MyViewModel(repository: dependencies.repository))
        self.user = user
        self.refreshKey = refreshKey
        self.onNotice = onNotice
    }

    public var body: some View {
        ZStack(alignment: .top) {
            MwSceneBackground(.sunset)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        MwGlassCircleButton(.gear, label: "my.settings", bundle: .module) { router.present(.settings) }
                            .accessibilityIdentifier("my.settings")
                    }
                    .padding(.horizontal, 16 * scale)
                    .frame(minHeight: 52 * scale)
                    .padding(.top, 54 * scale)
                    profile
                    levels.padding(.top, 20 * scale)
                    links.padding(.top, 22 * scale)
                }
                .padding(.bottom, MwTabBar<AppTab>.reservedHeight * scale)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .task(id: refreshKey) { await model.load() }
    }

    private var profile: some View {
        HStack(spacing: 12 * scale) {
            MwProfileAvatar()
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: user?.nickname ?? "")
                    .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                    .foregroundStyle(MwColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 0) {
                    Text(verbatim: "\(Self.jobName(user?.jobGroup)) · ").mwFont(.regular, 15, lineHeight: 22)
                    MwIconView(.flame).frame(width: 10.891 * scale, height: 14 * scale)
                    Text(verbatim: fmt("my.streak", user?.currentStreak ?? 0)).mwFont(.regular, 15, lineHeight: 22)
                }
                .foregroundStyle(MwColor.textSecondary)
                Text(verbatim: fmt("my.stats", 0, 0, model.translationCount ?? 0))
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
            }
        }
        .padding(.horizontal, 20 * scale)
        .accessibilityElement(children: .combine)
    }

    /// 직군(계약 JobGroup: 개발·기획·디자인·영업·HR·기타)은 그대로 보인다. 온보딩 전이면 "직군 미설정".
    static func jobName(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return String(localized: "my.job.unknown", bundle: .module) }
        return code
    }

    private var levels: some View {
        let score = user?.bestScore ?? 0
        let current = LevelRowSpec.current(code: user?.levelCode, score: score)
        let currentName = LevelRowSpec.all[current - 1].shortKey
        return VStack(alignment: .leading, spacing: 0) {
            MwSectionHeader(Text("my.levels.title", bundle: .module)) {
                (Text(currentName, bundle: .module) + Text(verbatim: fmt("my.levels.score", score)))
                    .mwFont(.semiBold, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.accentFill)
            }
            VStack(spacing: 0) {
                ForEach(LevelRowSpec.all, id: \.number) { spec in
                    if spec.number > 1 {
                        MwRowDivider()
                    }
                    levelRow(spec, state: spec.number < current ? .passed : spec.number == current ? .current : .locked)
                }
            }
            .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
            .mwCardShadow(scale)
        }
        .padding(.horizontal, 20 * scale)
    }

    enum LevelState {
        case passed, current, locked
    }

    private func levelRow(_ spec: LevelRowSpec, state: LevelState) -> some View {
        HStack(spacing: 14 * scale) {
            Text(verbatim: "Lv\(spec.number)")
                .font(MwFont.pretendard(.extraBold, size: 12 * scale))
                .foregroundStyle(spec.number == 1 ? MwColor.textStrong : Color(levelHex: 0x1F1A2E))
                .frame(width: 34 * scale, height: 34 * scale)
                .background(RoundedRectangle(cornerRadius: 11 * scale, style: .circular).fill(spec.badge))
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.nameKey, bundle: .module)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(state == .locked ? MwColor.textDisabled : MwColor.textPrimary)
                Text(spec.rangeKey, bundle: .module)
                    .mwFont(.regular, 14, lineHeight: 20)
                    .foregroundStyle(MwColor.textSecondary)
                    .padding(.top, 1 * scale)
            }
            .padding(.vertical, 13 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            switch state {
            case .passed: MwIconView(.checkCircle, color: Color(levelHex: 0x5DAE6B))
            case .current: MwStatusPill(Text("my.levels.now", bundle: .module), tone: .info)
            case .locked: MwIconView(.lock, color: MwColor.textDisabled)
            }
        }
        .padding(.horizontal, 18 * scale)
        .frame(minHeight: 56 * scale)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(
            state == .passed ? "my.levels.passed" : state == .current ? "my.levels.now" : "my.levels.locked",
            bundle: .module
        ))
    }

    private var links: some View {
        VStack(spacing: 0) {
            linkRow(
                LinkIcon(icon: .bikeLarge, color: MwColor.accentFill, fill: MwColor.accentSoftFill),
                title: Text("my.link.review", bundle: .module),
                value: Text(verbatim: Self.reminder)
            ) {
                onNotice("my.link.reviewComingSoon")
            }
            MwRowDivider()
            linkRow(
                LinkIcon(icon: .layersOutline, color: MwColor.jargonChipText, fill: MwColor.jargonChipFill),
                title: Text("my.link.projects", bundle: .module),
                value: Text(verbatim: fmt("my.link.projectCount", model.projectCount ?? 0))
            ) {
                router.select(.project)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
        .mwCardShadow(scale)
        .padding(.horizontal, 20 * scale)
    }

    static var reminder: String {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        comps.hour = 18
        return (Calendar(identifier: .gregorian).date(from: comps) ?? Date())
            .formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR")))
    }

    struct LinkIcon {
        let icon: MwIcon
        let color: Color
        let fill: Color
    }

    private func linkRow(
        _ badge: LinkIcon,
        title: Text,
        value: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14 * scale) {
                MwIconView(badge.icon, color: badge.color)
                    .frame(width: 34 * scale, height: 34 * scale)
                    .background(RoundedRectangle(cornerRadius: 11 * scale, style: .circular).fill(badge.fill))
                title.mwFont(.medium, 17, lineHeight: 24).foregroundStyle(MwColor.textPrimary).frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                value.font(MwFont.pretendard(.regular, size: 16 * scale)).foregroundStyle(MwColor.textSecondary)
                MwIconView(.chevronRight, color: MwColor.textDisabled)
            }
            .padding(.horizontal, 18 * scale)
            .frame(minHeight: 56 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    /// 등급 배지 색(Figma 51:2807~2871). 그림 성격의 값이라 토큰 밖.
    init(levelHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 카탈로그 문구 + 값(키는 점 표기만 쓴다 → 값은 %lld·%@ 자리표시자로 넣는다, check-xcstrings).
func fmt(_ key: String, _ args: CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key), bundle: .module), arguments: args)
}
