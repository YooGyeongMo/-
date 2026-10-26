import AuthenticationServices
import Domain
@testable import Platform
import Security
import Testing

struct PlatformAuthTests {
    @Test("Keychain 조회 조건: generic password, 서비스·계정") func baseQueryShape() {
        let query = KeychainTokenStore.baseQuery(service: "s", account: "a")
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "s")
        #expect(query[kSecAttrAccount as String] as? String == "a")
    }

    @Test("Apple 창을 닫으면 cancelled, 그 밖은 signInFailed") func mapsAuthorizationErrors() {
        #expect(AppleAuthorizationRunner.map(ASAuthorizationError(.canceled)) == .cancelled)
        #expect(AppleAuthorizationRunner.map(ASAuthorizationError(.failed)) == .signInFailed(message: nil))
        #expect(AppleAuthorizationRunner.map(URLError(.timedOut)) == .signInFailed(message: nil))
    }

    @Test("네이티브 redirectUri는 계약 format: uri를 만족한다") func redirectURIIsValidURL() {
        #expect(URL(string: AppleSignInCodeProvider.nativeRedirectURI)?.scheme == "https")
    }
}
