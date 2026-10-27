@testable import MwonmalUI
import SwiftUI
import Testing

struct MwLayoutTests {
    #if !os(macOS)
        @Test("사이즈 클래스 4조합: 둘 다 regular일 때만 wide(ADR-0006)") func fourCombinations() {
            #expect(MwLayout.from(horizontal: .regular, vertical: .regular) == .wide) // iPad 전체화면
            #expect(MwLayout.from(horizontal: .regular, vertical: .compact) == .compact) // iPhone Pro Max 가로
            #expect(MwLayout.from(horizontal: .compact, vertical: .regular) == .compact) // iPhone 세로, iPad Slide Over
            #expect(MwLayout.from(horizontal: .compact, vertical: .compact) == .compact)
            #expect(MwLayout.from(horizontal: nil, vertical: nil) == .compact)
        }
    #endif

    @Test("배율: 좁은 화면은 폭/393, 1.25에서 멈춘다") func scale() {
        #expect(MwFrame.scale(forWidth: 393) == 1)
        #expect(abs(MwFrame.scale(forWidth: 375) - 375.0 / 393.0) < 0.0001)
        #expect(MwFrame.scale(forWidth: 1280) == 1.25)
    }
}
