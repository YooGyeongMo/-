#if DEBUG
    import Domain
    import Foundation

    /// 로컬 서버 E2E 전용 로그인(`dev:<이름>`, ADR-0020). Debug 빌드에서 실행 인자 `-MWDevLogin <이름>`을 줄 때만 쓴다.
    /// 서버도 local·test 에서만 이 code를 받는다. Release 빌드에는 이 타입이 없다.
    public struct DevCodeProvider: OAuthCodeProviding {
        public let provider: OAuthProvider = .apple
        private let name: String

        public init(name: String) {
            self.name = name
        }

        public func requestCode() async throws -> OAuthCode {
            OAuthCode(provider: .apple, code: "dev:\(name)", redirectUri: AppleSignInCodeProvider.nativeRedirectURI)
        }

        /// 실행 인자에서 이름을 읽는다(`-MWDevLogin alice`). 없거나 형식이 틀리면 nil.
        public static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> DevCodeProvider? {
            guard let i = arguments.firstIndex(of: "-MWDevLogin"), i + 1 < arguments.count else { return nil }
            let name = arguments[i + 1]
            let allowed = name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == "_") }
            guard !name.isEmpty, name.count <= 32, allowed else { return nil }
            return DevCodeProvider(name: name)
        }
    }
#endif
