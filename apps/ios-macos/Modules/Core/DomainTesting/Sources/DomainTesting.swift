#if DEBUG
    import Domain

    /// DomainTesting 모듈(ADR-0016). 모든 Tests·Example·Preview가 같이 쓰는 Fake/Spy.
    /// 릴리스 빌드에서는 빈 모듈이 된다(`#if DEBUG`).
    public enum DomainTestingModule {
        public static let name = "DomainTesting"
        static let domain = DomainModule.name
    }

    public extension UserProfile {
        static let sample = UserProfile(id: 8, nickname: "판교뉴비123456", email: "sub-1@apple.invalid", jobGroup: nil)
    }

    public extension OAuthCode {
        static let sample = OAuthCode(provider: .apple, code: "fake-code", redirectUri: "https://example.invalid/auth/apple")
    }

    /// 메모리 토큰 보관소. `failSave`로 Keychain 실패를 흉내 낸다.
    public actor InMemoryTokenStore: TokenStore {
        public private(set) var token: String?
        public var failSave = false

        public init(token: String? = nil) {
            self.token = token
        }

        public func setFailSave(_ value: Bool) {
            failSave = value
        }

        public func read() async -> String? {
            token
        }

        public func save(_ token: String) async throws {
            if failSave {
                throw DomainError.unknown
            }
            self.token = token
        }

        public func clear() async throws {
            token = nil
        }
    }

    /// 정해 둔 결과를 돌려주는 code 제공자.
    public struct FakeCodeProvider: OAuthCodeProviding {
        public let provider: OAuthProvider = .apple
        private let result: Result<OAuthCode, DomainError>

        public init(_ result: Result<OAuthCode, DomainError> = .success(.sample)) {
            self.result = result
        }

        public func requestCode() async throws -> OAuthCode {
            try result.get()
        }
    }

    /// 호출을 기록하고 정해 둔 결과를 돌려주는 리포지토리.
    public actor FakeAuthRepository: AuthRepository {
        public var signInResult: Result<(accessToken: String, result: SignInResult), DomainError>
        public var meResult: Result<UserProfile, DomainError>
        public private(set) var signInCodes: [OAuthCode] = []
        public private(set) var meCalls = 0

        public init(
            signIn: Result<(accessToken: String, result: SignInResult), DomainError> = .success(
                ("server-token", SignInResult(user: .sample, isNewUser: true, needsOnboarding: true))
            ),
            profile: Result<UserProfile, DomainError> = .success(.sample)
        ) {
            signInResult = signIn
            meResult = profile
        }

        public func signIn(with code: OAuthCode) async throws -> (accessToken: String, result: SignInResult) {
            signInCodes.append(code)
            return try signInResult.get()
        }

        public func me() async throws -> UserProfile {
            meCalls += 1
            return try meResult.get()
        }
    }
#endif
