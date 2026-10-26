import Domain
import Foundation
import Security

/// 서버 토큰을 Keychain에 둔다(12번 D-11). 기기 잠금 해제 후 접근, 이 기기에만(백업·이전 안 됨).
public actor KeychainTokenStore: TokenStore {
    public static let defaultService = "kr.mwonmal.app.auth"
    let service: String
    let account: String

    public init(service: String = defaultService, account: String = "accessToken") {
        self.service = service
        self.account = account
    }

    public func read() async -> String? {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) async throws {
        let query = Self.baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw DomainError.server(code: "KEYCHAIN_\(status)", message: nil) }
    }

    public func clear() async throws {
        let status = SecItemDelete(Self.baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DomainError.server(code: "KEYCHAIN_\(status)", message: nil)
        }
    }

    /// 조회·삭제 공통 조건. macOS도 데이터 보호 Keychain을 써서 iOS와 같은 의미가 되게 한다.
    static func baseQuery(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
