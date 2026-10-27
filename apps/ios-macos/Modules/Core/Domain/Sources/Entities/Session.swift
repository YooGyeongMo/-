import Foundation

/// 로그인 제공자. v1.0은 Apple만(ADR-0013, #90에서 카카오·Google).
public enum OAuthProvider: String, Sendable, CaseIterable {
    case apple
}

/// 제공자 인증 화면에서 받은 일회용 code. 서버가 Apple과 교환한다(ADR-0014).
public struct OAuthCode: Sendable, Equatable {
    public let provider: OAuthProvider
    public let code: String
    /// 계약 v1.0 필수 필드. 네이티브 흐름이라 서버는 Apple에 보내지 않는다(ADR-0014 §3).
    public let redirectUri: String

    public init(provider: OAuthProvider, code: String, redirectUri: String) {
        self.provider = provider
        self.code = code
        self.redirectUri = redirectUri
    }
}

/// 화면이 쓰는 사용자 요약. DTO는 Data 밖으로 나오지 않는다.
public struct UserProfile: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let nickname: String
    public let email: String?
    /// 온보딩 전이면 nil.
    public let jobGroup: String?
    /// 판교 등급 코드(OUTSIDER…LOCAL). 진단 전이면 nil → 화면은 Lv1로 본다.
    public let levelCode: String?
    public let bestScore: Int
    public let currentStreak: Int
    public let currentProjectId: Int64?

    public init(
        id: Int64, nickname: String, email: String?, jobGroup: String?,
        levelCode: String? = nil, bestScore: Int = 0, currentStreak: Int = 0, currentProjectId: Int64? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.email = email
        self.jobGroup = jobGroup
        self.levelCode = levelCode
        self.bestScore = bestScore
        self.currentStreak = currentStreak
        self.currentProjectId = currentProjectId
    }
}

public struct SignInResult: Sendable, Equatable {
    public let user: UserProfile
    public let isNewUser: Bool
    public let needsOnboarding: Bool

    public init(user: UserProfile, isNewUser: Bool, needsOnboarding: Bool) {
        self.user = user
        self.isNewUser = isNewUser
        self.needsOnboarding = needsOnboarding
    }
}

/// 앱 시작 시 세션 상태.
public enum SessionState: Sendable, Equatable {
    case signedOut
    case signedIn(UserProfile)
    /// 토큰은 있지만 서버에 닿지 못했다(오프라인 등). 토큰은 지우지 않는다.
    case unverified
}
