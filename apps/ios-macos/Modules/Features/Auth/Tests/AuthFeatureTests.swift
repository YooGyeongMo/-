import AuthenticationServices
@testable import AuthFeature
import Testing

struct AuthFeatureTests {
    @Test("모듈 이름") func moduleName() {
        #expect(AuthFeatureModule.name == "AuthFeature")
    }

    @Test("Apple 창을 닫으면 cancelled, 그 밖의 실패는 failed") func mapsFailures() {
        #expect(AuthRootView.outcome(.failure(ASAuthorizationError(.canceled))) == .cancelled)
        #expect(AuthRootView.outcome(.failure(ASAuthorizationError(.failed))) == .failed)
        #expect(AuthRootView.outcome(.failure(ASAuthorizationError(.unknown))) == .failed)
    }

    @Test("히어로 높이: Figma 비율이 상한, 남는 높이가 적으면 줄되 220 아래로는 안 간다", arguments: [
        (393.0, 1000.0, 470.0), // 넉넉함 → Figma 그대로
        (393.0, 300.0, 300.0), // 빠듯함 → 남은 만큼
        (393.0, 100.0, 220.0), // 아주 빠듯함(큰 글자) → 최소, 나머지는 스크롤
        (100.0, 50.0, 100.0 * 470 / 393), // 좁은 화면 → 비율 높이가 최소보다 작으면 비율 높이
    ])
    func heroHeight(width: Double, available: Double, expected: Double) {
        #expect(abs(AuthRootView.heroHeight(width: width, available: available) - expected) < 0.001)
    }

    @Test("카카오·Google은 각자 안내 문구가 있다") func comingSoonKeys() {
        let keys = OtherSignInProvider.allCases.map(AuthRootView.comingSoonKey)
        #expect(Set(keys).count == OtherSignInProvider.allCases.count)
    }
}
