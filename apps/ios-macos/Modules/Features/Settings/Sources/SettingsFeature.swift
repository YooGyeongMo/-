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

    static let all: [LevelRowSpec] = [
        LevelRowSpec(number: 1, code: "OUTSIDER", nameKey: "my.level.1.name", rangeKey: "my.level.1.range", badge: Color(levelHex: 0xC9D6E8), minScore: 0),
        LevelRowSpec(number: 2, code: "TOURIST", nameKey: "my.level.2.name", rangeKey: "my.level.2.range", badge: Color(levelHex: 0x8CCBEA), minScore: 20),
        LevelRowSpec(number: 3, code: "SETTLER", nameKey: "my.level.3.name", rangeKey: "my.level.3.range", badge: Color(levelHex: 0x5DB5B1), minScore: 40),
        LevelRowSpec(number: 4, code: "NATIVE", nameKey: "my.level.4.name", rangeKey: "my.level.4.range", badge: Color(levelHex: 0x5DAE6B), minScore: 65),
        LevelRowSpec(number: 5, code: "LOCAL", nameKey: "my.level.5.name", rangeKey: "my.level.5.range", badge: Color(levelHex: 0xF7C948), minScore: 85),
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
    @State private var model: MyViewModel
    let user: UserProfile?
    let refreshKey: Int
    let onNotice: (LocalizedStringKey) -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var s

    public init(dependencies: SettingsDependencies, user: UserProfile?, refreshKey: Int = 0, onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }) {
        _model = State(initialValue: MyViewModel(repository: dependencies.repository))
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
                    .padding(.horizontal, 16 * s)
                    .frame(height: 52 * s)
                    .padding(.top, 54 * s)
                    profile
                    levels.padding(.top, 20 * s)
                    links.padding(.top, 22 * s)
                }
                .padding(.bottom, MwTabBar<AppTab>.reservedHeight * s)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .task(id: refreshKey) { await model.load() }
    }

    private var profile: some View {
        HStack(spacing: 12 * s) {
            MwProfileAvatar()
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: user?.nickname ?? "")
                    .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                    .foregroundStyle(MwColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 0) {
                    Text(verbatim: "\(Self.jobName(user?.jobGroup)) · ").mwFont(.regular, 15, lineHeight: 22)
                    MwIconView(.flame).frame(width: 10.891 * s, height: 14 * s)
                    Text(verbatim: L("my.streak", user?.currentStreak ?? 0)).mwFont(.regular, 15, lineHeight: 22)
                }
                .foregroundStyle(MwColor.textSecondary)
                Text(verbatim: L("my.stats", 0, 0, model.translationCount ?? 0))
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
            }
        }
        .padding(.horizontal, 20 * s)
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
        let currentName = LevelRowSpec.all[current - 1].nameKey
        return VStack(alignment: .leading, spacing: 0) {
            MwSectionHeader(Text("my.levels.title", bundle: .module)) {
                (Text(currentName, bundle: .module) + Text(verbatim: L("my.levels.score", score)))
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
            .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .circular))
            .mwCardShadow(s)
        }
        .padding(.horizontal, 20 * s)
    }

    enum LevelState {
        case passed, current, locked
    }

    private func levelRow(_ spec: LevelRowSpec, state: LevelState) -> some View {
        HStack(spacing: 14 * s) {
            Text(verbatim: "Lv\(spec.number)")
                .font(MwFont.pretendard(.extraBold, size: 12 * s))
                .foregroundStyle(spec.number == 1 ? MwColor.textStrong : Color(levelHex: 0x1F1A2E))
                .frame(width: 34 * s, height: 34 * s)
                .background(RoundedRectangle(cornerRadius: 11 * s, style: .circular).fill(spec.badge))
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.nameKey, bundle: .module)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(state == .locked ? MwColor.textDisabled : MwColor.textPrimary)
                Text(spec.rangeKey, bundle: .module)
                    .mwFont(.regular, 14, lineHeight: 20)
                    .foregroundStyle(MwColor.textSecondary)
                    .padding(.top, 1 * s)
            }
            .padding(.vertical, 13 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            switch state {
            case .passed: MwIconView(.checkCircle, color: Color(levelHex: 0x5DAE6B))
            case .current: MwStatusPill(Text("my.levels.now", bundle: .module), tone: .info)
            case .locked: MwIconView(.lock, color: MwColor.textDisabled)
            }
        }
        .padding(.horizontal, 18 * s)
        .frame(minHeight: 56 * s)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(state == .passed ? "my.levels.passed" : state == .current ? "my.levels.now" : "my.levels.locked", bundle: .module))
    }

    private var links: some View {
        VStack(spacing: 0) {
            linkRow(icon: .bikeLarge, iconColor: MwColor.accentFill, iconFill: MwColor.accentSoftFill, title: Text("my.link.review", bundle: .module), value: Text(verbatim: Self.reminder)) {
                onNotice("my.link.reviewComingSoon")
            }
            MwRowDivider()
            linkRow(icon: .layersOutline, iconColor: MwColor.jargonChipText, iconFill: MwColor.jargonChipFill, title: Text("my.link.projects", bundle: .module), value: Text(verbatim: L("my.link.projectCount", model.projectCount ?? 0))) {
                router.select(.project)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .circular))
        .mwCardShadow(s)
        .padding(.horizontal, 20 * s)
    }

    static var reminder: String {
        var c = DateComponents()
        c.year = 2026
        c.month = 1
        c.day = 1
        c.hour = 18
        return (Calendar(identifier: .gregorian).date(from: c) ?? Date()).formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR")))
    }

    private func linkRow(icon: MwIcon, iconColor: Color, iconFill: Color, title: Text, value: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14 * s) {
                MwIconView(icon, color: iconColor)
                    .frame(width: 34 * s, height: 34 * s)
                    .background(RoundedRectangle(cornerRadius: 11 * s, style: .circular).fill(iconFill))
                title.mwFont(.medium, 17, lineHeight: 24).foregroundStyle(MwColor.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                value.font(MwFont.pretendard(.regular, size: 16 * s)).foregroundStyle(MwColor.textSecondary)
                MwIconView(.chevronRight, color: MwColor.textDisabled)
            }
            .padding(.horizontal, 18 * s)
            .frame(minHeight: 56 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 설정 시트

@MainActor @Observable
public final class SettingsViewModel {
    public private(set) var aiConsent = false
    public var showConsentNotice = false
    private let consent: any AIConsentStore

    public init(consent: any AIConsentStore) {
        self.consent = consent
    }

    public func load() async {
        aiConsent = await consent.isGranted()
    }

    /// 켤 때는 고지문을 먼저 보여 주고 확인을 받는다(#25). 끌 때는 바로.
    public func requestToggle(_ on: Bool) async {
        if on {
            showConsentNotice = true
        } else {
            await consent.setGranted(false)
            aiConsent = false
        }
    }

    public func confirmConsent() async {
        await consent.setGranted(true)
        aiConsent = true
        showConsentNotice = false
    }
}

/// 설정(Figma에 시안 없음 → A-09 카드·행 모양을 그대로 씀). AI 외부 전송 옵트인(기본 꺼짐) · 로그아웃 · 정보.
public struct SettingsSheet: View {
    @State private var model: SettingsViewModel
    let nickname: String?
    let email: String?
    let onSignOut: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var s
    @State private var confirmSignOut = false

    public init(consent: any AIConsentStore, nickname: String?, email: String?, onSignOut: @escaping () -> Void) {
        _model = State(initialValue: SettingsViewModel(consent: consent))
        self.nickname = nickname
        self.email = email
        self.onSignOut = onSignOut
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * s)
                HStack {
                    Text("settings.title", bundle: .module)
                        .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                        .foregroundStyle(MwColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    MwGlassCircleButton(.close, diameter: 32, label: "settings.close", bundle: .module) { router.dismissSheet() }
                }
                .padding(.top, 14 * s)
                MwSectionHeader(Text("settings.ai.section", bundle: .module)).padding(.top, 20 * s)
                aiCard
                MwSectionHeader(Text("settings.account.section", bundle: .module)).padding(.top, 20 * s)
                accountCard
                MwSectionHeader(Text("settings.about.section", bundle: .module)).padding(.top, 20 * s)
                aboutCard
            }
            .padding(.horizontal, 20 * s)
            .padding(.bottom, 32 * s)
        }
        .background(MwColor.canvas.ignoresSafeArea())
        .task { await model.load() }
        .sheet(isPresented: $model.showConsentNotice) {
            ConsentNotice {
                Task { await model.confirmConsent() }
            } onCancel: {
                model.showConsentNotice = false
            }
            .presentationDetents([.medium, .large])
            .environment(\.mwScale, s)
        }
        .confirmationDialog(Text("settings.signOut.confirm", bundle: .module), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(role: .destructive) {
                onSignOut()
            } label: {
                Text("settings.signOut", bundle: .module)
            }
        }
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Toggle(isOn: Binding(get: { model.aiConsent }, set: { on in Task { await model.requestToggle(on) } })) {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text("settings.ai.toggle", bundle: .module).mwFont(.medium, 17, lineHeight: 24).foregroundStyle(MwColor.textPrimary)
                    Text(model.aiConsent ? "settings.ai.on" : "settings.ai.off", bundle: .module)
                        .mwFont(.regular, 14, lineHeight: 20)
                        .foregroundStyle(MwColor.textSecondary)
                }
            }
            .tint(MwColor.accentFill)
            .accessibilityIdentifier("settings.aiToggle")
            Text("settings.ai.footnote", bundle: .module)
                .mwFont(.regular, 13, lineHeight: 19)
                .foregroundStyle(MwColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18 * s)
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
        .mwCardShadow(s)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("settings.account.signedInAs", bundle: .module).mwFont(.medium, 17, lineHeight: 24).foregroundStyle(MwColor.textPrimary)
                Spacer()
                Text(verbatim: nickname ?? "").mwFont(.regular, 15).foregroundStyle(MwColor.textSecondary).lineLimit(1)
            }
            .padding(.horizontal, 18 * s)
            .frame(minHeight: 56 * s)
            MwRowDivider()
            Button {
                confirmSignOut = true
            } label: {
                Text("settings.signOut", bundle: .module)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(MwColor.urgentText)
                    .frame(maxWidth: .infinity, minHeight: 56 * s, alignment: .leading)
                    .padding(.horizontal, 18 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.signOut")
        }
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .circular))
        .mwCardShadow(s)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("settings.about.version", bundle: .module).mwFont(.medium, 17, lineHeight: 24).foregroundStyle(MwColor.textPrimary)
                Spacer()
                Text(verbatim: Self.version).mwFont(.regular, 15).foregroundStyle(MwColor.textSecondary)
            }
            .padding(.horizontal, 18 * s)
            .frame(minHeight: 56 * s)
            MwRowDivider()
            Text("settings.about.font", bundle: .module)
                .mwFont(.regular, 13, lineHeight: 19)
                .foregroundStyle(MwColor.textSecondary)
                .padding(18 * s)
        }
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .circular))
        .mwCardShadow(s)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// 옵트인 고지문(ADR-0008, #25 심사 자료). 켜기 전에 반드시 읽게 한다.
struct ConsentNotice: View {
    let onAgree: () -> Void
    let onCancel: () -> Void
    @Environment(\.mwScale) private var s

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * s) {
                Text("settings.consent.title", bundle: .module)
                    .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                    .foregroundStyle(MwColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(["settings.consent.point1", "settings.consent.point2", "settings.consent.point3", "settings.consent.point4"], id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                        Text(verbatim: "•")
                        Text(LocalizedStringKey(key), bundle: .module).fixedSize(horizontal: false, vertical: true)
                    }
                    .mwFont(.regular, 15, lineHeight: 22)
                    .foregroundStyle(MwColor.textPrimary)
                }
                Button(action: onAgree) {
                    Text("settings.consent.agree", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * s))
                }
                .buttonStyle(MwPrimaryButtonStyle(height: 52))
                .padding(.top, 8 * s)
                .accessibilityIdentifier("consent.agree")
                Button(action: onCancel) {
                    Text("settings.consent.cancel", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * s))
                }
                .buttonStyle(MwSecondaryButtonStyle(height: 48))
            }
            .padding(20 * s)
        }
        .background(MwColor.canvas.ignoresSafeArea())
    }
}

private extension Color {
    /// 등급 배지 색(Figma 51:2807~2871). 그림 성격의 값이라 토큰 밖.
    init(levelHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 카탈로그 문구 + 값(키는 점 표기만 쓴다 → 값은 %lld·%@ 자리표시자로 넣는다, check-xcstrings).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key), bundle: .module), arguments: args)
}
