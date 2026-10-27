import Domain
import FeatureKit
import MwonmalUI
import Observation
import Routing
import SwiftUI

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
    @Environment(\.mwScale) private var scale
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
                MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * scale)
                HStack {
                    Text("settings.title", bundle: .module)
                        .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                        .foregroundStyle(MwColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    MwGlassCircleButton(.close, diameter: 32, label: "settings.close", bundle: .module) { router.dismissSheet() }
                }
                .padding(.top, 14 * scale)
                MwSectionHeader(Text("settings.ai.section", bundle: .module)).padding(.top, 20 * scale)
                aiCard
                MwSectionHeader(Text("settings.account.section", bundle: .module)).padding(.top, 20 * scale)
                accountCard
                MwSectionHeader(Text("settings.about.section", bundle: .module)).padding(.top, 20 * scale)
                aboutCard
            }
            .padding(.horizontal, 20 * scale)
            .padding(.bottom, 32 * scale)
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
            .environment(\.mwScale, scale)
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
        VStack(alignment: .leading, spacing: 10 * scale) {
            Toggle(isOn: Binding(get: { model.aiConsent }, set: { on in Task { await model.requestToggle(on) } })) {
                VStack(alignment: .leading, spacing: 2 * scale) {
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
        .padding(18 * scale)
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .mwCardShadow(scale)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("settings.account.signedInAs", bundle: .module).mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(MwColor.textPrimary)
                Spacer()
                Text(verbatim: nickname ?? "").mwFont(.regular, 15).foregroundStyle(MwColor.textSecondary).lineLimit(1)
            }
            .padding(.horizontal, 18 * scale)
            .frame(minHeight: 56 * scale)
            MwRowDivider()
            Button {
                confirmSignOut = true
            } label: {
                Text("settings.signOut", bundle: .module)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(MwColor.urgentText)
                    .frame(maxWidth: .infinity, minHeight: 56 * scale, alignment: .leading)
                    .padding(.horizontal, 18 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.signOut")
        }
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
        .mwCardShadow(scale)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("settings.about.version", bundle: .module).mwFont(.medium, 17, lineHeight: 24).foregroundStyle(MwColor.textPrimary)
                Spacer()
                Text(verbatim: Self.version).mwFont(.regular, 15).foregroundStyle(MwColor.textSecondary)
            }
            .padding(.horizontal, 18 * scale)
            .frame(minHeight: 56 * scale)
            MwRowDivider()
            Text("settings.about.font", bundle: .module)
                .mwFont(.regular, 13, lineHeight: 19)
                .foregroundStyle(MwColor.textSecondary)
                .padding(18 * scale)
        }
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
        .mwCardShadow(scale)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(ver) (\(build))"
    }
}

/// 옵트인 고지문(ADR-0008, #25 심사 자료). 켜기 전에 반드시 읽게 한다.
struct ConsentNotice: View {
    let onAgree: () -> Void
    let onCancel: () -> Void
    @Environment(\.mwScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * scale) {
                Text("settings.consent.title", bundle: .module)
                    .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                    .foregroundStyle(MwColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(
                    ["settings.consent.point1", "settings.consent.point2", "settings.consent.point3", "settings.consent.point4"],
                    id: \.self
                ) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                        Text(verbatim: "•")
                        Text(LocalizedStringKey(key), bundle: .module).fixedSize(horizontal: false, vertical: true)
                    }
                    .mwFont(.regular, 15, lineHeight: 22)
                    .foregroundStyle(MwColor.textPrimary)
                }
                Button(action: onAgree) {
                    Text("settings.consent.agree", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * scale))
                }
                .buttonStyle(MwPrimaryButtonStyle(height: 52))
                .padding(.top, 8 * scale)
                .accessibilityIdentifier("consent.agree")
                Button(action: onCancel) {
                    Text("settings.consent.cancel", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * scale))
                }
                .buttonStyle(MwSecondaryButtonStyle(height: 48))
            }
            .padding(20 * scale)
        }
        .background(MwColor.canvas.ignoresSafeArea())
    }
}
