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
}
