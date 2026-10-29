import MwonmalUI
import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// MotionLab(ADR-0012 최소판): 프리셋 3개를 눌러 보고, 값을 슬라이더로 바꾸고, 바꾼 묶음을 JSON으로 복사한다.
/// 동작 줄이기 스위치는 `.reduced` 테마를 주입해 시스템 설정 없이 확인한다.
struct MotionLab: View {
    @State private var theme = MwMotionTheme.default
    @State private var isFlipped = false
    @State private var isDecoding = true
    @State private var showsToast = false
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Toggle("동작 줄이기(.reduced 주입)", isOn: $theme.isReduced)
            }
            Section("카드 뒤집기 · cardFlip") {
                HStack {
                    Spacer()
                    face(MwColor.accentFill, "판교어")
                        .mwCardFlip(isFlipped: isFlipped) { face(MwColor.surfaceMuted, "쉬운 말") }
                        .onTapGesture { isFlipped.toggle() }
                    Spacer()
                }
                .padding(.vertical, 12)
                slider("원근", value: $theme.cardFlip.perspective, in: 0 ... 1)
                slider("들림", value: $theme.cardFlip.liftScale, in: 1 ... 1.1)
            }
            Section("해석 중 맥박 · decodingPulse") {
                MwDecodingPlaceholder(Text(verbatim: "해석하고 있어요"))
                    .opacity(isDecoding ? 1 : 0)
                Toggle("맥박", isOn: $isDecoding)
                slider("주기(초)", value: $theme.decodingPulse.period, in: 0.6 ... 2.4)
                slider("가장 옅을 때", value: $theme.decodingPulse.minOpacity, in: 0.2 ... 1)
            }
            Section("아래 오버레이 · sheetPresent") {
                ZStack(alignment: .bottom) {
                    Color.clear.frame(minHeight: 90)
                    if showsToast {
                        MwToast(Text(verbatim: "복습 카드로 담았어요")).mwSheetTransition()
                    }
                }
                Button(showsToast ? "내리기" : "올리기") {
                    withAnimation(MwMotion.sheet(theme, reduceMotion: false)) { showsToast.toggle() }
                }
                slider("거리(pt)", value: $theme.sheetPresent.travel, in: 0 ... 80)
            }
            Section {
                Button(copied ? "복사했어요" : "테마 JSON 복사") { copy() }
            }
        }
        .mwMotionTheme(theme)
        .navigationTitle("MotionLab")
    }

    private func face(_ color: Color, _ label: String) -> some View {
        Text(verbatim: label)
            .mwFont(.bold, 17)
            .foregroundStyle(MwColor.textPrimary)
            .frame(width: 180, height: 110)
            .background(RoundedRectangle(cornerRadius: 22).fill(color))
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack {
            Text(verbatim: title)
            Slider(value: value, in: range)
            Text(verbatim: value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
        }
    }

    private func copy() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(theme), let json = String(data: data, encoding: .utf8) else { return }
        #if os(iOS)
            UIPasteboard.general.string = json
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        #endif
        copied = true
    }
}
