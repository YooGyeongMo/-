import Domain
import Foundation

/// AI 외부 전송 동의를 기기에 저장한다(기본 꺼짐, ADR-0008). 로그아웃하면 지운다(#25).
public struct UserDefaultsAIConsentStore: AIConsentStore {
    static let key = "mw.ai.externalConsent"
    /// nil = `.standard`. 테스트는 자기 이름의 저장소를 쓴다.
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func isGranted() async -> Bool {
        defaults.bool(forKey: Self.key)
    }

    public func setGranted(_ granted: Bool) async {
        defaults.set(granted, forKey: Self.key)
    }
}
