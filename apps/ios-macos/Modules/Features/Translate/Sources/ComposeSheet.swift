import Domain
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// 붙여넣기 시트(iOS 판 W-01, Figma 51:5964 웹 시안을 A-06 시트 틀에 맞춤).
/// 붙여넣기·캡처 고르기(캡처 OCR은 v1.1) → "받은 말을 그대로 붙여넣으세요" → 흰 입력 카드(파란 테두리)
/// → 방향 칩·글자 수·해석하기 버튼. 해석이 끝나면 같은 자리에서 결과 시트로 바뀐다.
public struct ComposeSheet: View {
    @ViewModelState private var model: ComposeViewModel
    let aiConsent: Bool
    let onResult: (Domain.Translation) -> Void
    let onNotice: (LocalizedStringKey) -> Void
    let dependencies: TranslateDependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var scale
    @Environment(\.mwLayout) private var layout
    @FocusState private var focused: Bool

    public init(
        dependencies: TranslateDependencies,
        aiConsent: Bool,
        onResult: @escaping (Domain.Translation) -> Void,
        onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }
    ) {
        _model = ViewModelState(wrappedValue: ComposeViewModel(dependencies: dependencies))
        self.dependencies = dependencies
        self.aiConsent = aiConsent
        self.onResult = onResult
        self.onNotice = onNotice
    }

    public var body: some View {
        // 키보드가 올라와도 버튼·안내가 가려지지 않게 스크롤, 끌면 키보드가 내려간다(QA H3).
        ScrollView {
            if layout == .wide {
                // 넓은 화면(웹 W-01): 가운데 입력 카드 + 오른쪽 최근 해석 열. 시트가 아니라 상세 영역의 한 페이지.
                HStack(alignment: .top, spacing: 24) {
                    sheetContent.frame(maxWidth: MwLayout.readableWidth)
                    RecentTranslationsAside(dependencies: dependencies)
                        .frame(width: MwLayout.asideWidth)
                        .padding(.top, 24)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            } else {
                sheetContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(MwColor.canvas.ignoresSafeArea())
        .onAppear { focused = true }
        .onDisappear { model.cancel() }
        .onChange(of: model.state) { _, state in
            if case let .failed(reason) = state {
                AccessibilityNotification.Announcement(Self.message(reason)).post()
            }
        }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if layout == .compact {
                MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * scale)
            }
            HStack {
                modePicker
                Spacer()
                MwGlassCircleButton(.close, diameter: 32, label: "translate.compose.close", bundle: .module) {
                    model.cancel()
                    router.dismissSheet()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("compose.close")
            }
            .padding(.top, 14 * scale)
            Text("translate.compose.title", bundle: .module)
                .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                .foregroundStyle(MwColor.textPrimary)
                .padding(.top, 12 * scale)
                .accessibilityAddTraits(.isHeader)
            consentHint.padding(.top, 8 * scale)
            editorCard.padding(.top, 16 * scale)
            if case let .failed(reason) = model.state {
                Label { Text(Self.message(reason)) } icon: { Image(systemName: "exclamationmark.circle") }
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.urgentText)
                    .padding(.top, 10 * scale)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("compose.error")
            }
        }
        .padding(.horizontal, 20 * scale)
        .padding(.bottom, 24 * scale)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeItem(icon: .clip, Text("translate.compose.mode.paste", bundle: .module), selected: true) {}
            modeItem(icon: nil, Text("translate.compose.mode.capture", bundle: .module), selected: false) {
                onNotice("translate.compose.captureComingSoon")
            }
        }
        .padding(4 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .circular).fill(MwColor.chipFill))
    }

    private func modeItem(icon: MwIcon?, _ title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6 * scale) {
                if let icon {
                    MwIconView(icon, color: selected ? MwColor.textPrimary : MwColor.textSecondary)
                }
                title.mwFont(.bold, 13).foregroundStyle(selected ? MwColor.textPrimary : MwColor.textSecondary)
            }
            .padding(.horizontal, 14 * scale)
            .frame(minHeight: 32 * scale)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10 * scale, style: .circular).fill(MwColor.surface).mwCardShadow(scale)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6 * scale) {
                MwSourceChip(icon: .clip, Text("translate.compose.sourceChip", bundle: .module))
                Spacer()
                if model.text.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            model.text = String(first.prefix(TranslateUseCase.maxLength * 2))
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(MwColor.accentFill)
                }
            }
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("translate.compose.placeholder", bundle: .module)
                        .mwFont(.regular, 17, lineHeight: 26)
                        .foregroundStyle(MwColor.textTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.text)
                    .focused($focused)
                    .font(MwFont.pretendard(.regular, size: 17 * scale))
                    .lineSpacing((26 - 17 * MwTextStyle.naturalLineHeight) * scale)
                    .foregroundStyle(MwColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140 * scale, maxHeight: 260 * scale)
                    .onChange(of: model.text) { _, _ in model.clearError() }
                    .accessibilityLabel(Text("translate.compose.placeholder", bundle: .module))
                    .accessibilityIdentifier("compose.editor")
            }
            .padding(.top, 10 * scale)
            // swiftlint:disable:next no_fixed_height - 1pt 구분선·빛 줄(글자 없음)
            Rectangle().fill(MwColor.separator).frame(height: 1).padding(.top, 12 * scale)
            HStack(spacing: 8 * scale) {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 11 * scale, weight: .bold))
                    Text("translate.compose.direction", bundle: .module).mwFont(.bold, 12)
                }
                .foregroundStyle(MwColor.accentFill)
                .padding(.horizontal, 8 * scale)
                .frame(minHeight: 26 * scale)
                .background(RoundedRectangle(cornerRadius: 7 * scale, style: .circular).fill(MwColor.accentSoftFill))
                Spacer()
                Text(verbatim: "\(model.length) / \(TranslateUseCase.maxLength)")
                    .mwFont(.regular, 13)
                    .foregroundStyle(model.length > TranslateUseCase.maxLength ? MwColor.urgentText : MwColor.textSecondary)
                    .monospacedDigit()
                    .accessibilityLabel(Text(verbatim: fmt("translate.compose.count", model.length, TranslateUseCase.maxLength)))
            }
            .padding(.top, 12 * scale)
            Button {
                Task {
                    if let result = await model.submit() {
                        onResult(result)
                    }
                }
            } label: {
                HStack(spacing: 8 * scale) {
                    if model.state == .translating {
                        ProgressView().tint(MwColor.accentOnFill)
                        Text("translate.compose.submitting", bundle: .module)
                    } else {
                        MwIconView(.sparkles, color: MwColor.accentOnFill)
                        Text("translate.compose.submit", bundle: .module)
                    }
                }
                .font(MwFont.pretendard(.semiBold, size: 17 * scale))
            }
            .buttonStyle(MwPrimaryButtonStyle(height: 52, radius: 18))
            .keyboardShortcut(.return, modifiers: .command) // ⌘↩ (Mac·iPad 키보드, ADR-0006)
            .disabled(!model.canSubmit)
            .padding(.top, 14 * scale)
            .accessibilityIdentifier("compose.submit")
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 16 * scale)
        .background(RoundedRectangle(cornerRadius: 24 * scale, style: .circular).fill(MwColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 24 * scale, style: .circular).strokeBorder(MwColor.accentFill, lineWidth: 1))
        .mwRaisedShadow(scale)
    }

    @ViewBuilder private var consentHint: some View {
        if !aiConsent {
            Button {
                router.present(.settings)
            } label: {
                (Text("translate.compose.consentOff", bundle: .module) + Text(verbatim: " ") + Text(
                    "translate.compose.consentLink",
                    bundle: .module
                ).underline())
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    static func message(_ reason: ComposeViewModel.FailureReason) -> String {
        switch reason {
        case .empty: String(localized: "translate.compose.error.empty", bundle: .module)
        case .tooLong: String(localized: "translate.compose.error.tooLong", bundle: .module)
        case .offline: String(localized: "translate.compose.error.offline", bundle: .module)
        case let .busy(seconds):
            if let seconds, seconds > 0 {
                fmt("translate.compose.error.busySeconds", seconds)
            } else {
                String(localized: "translate.compose.error.busy", bundle: .module)
            }
        case let .server(message): message ?? String(localized: "translate.compose.error.generic", bundle: .module)
        }
    }
}
