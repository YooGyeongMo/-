import Domain
import Foundation
import MwonmalAPI

/// `AuthRepository` 서버 구현(계약 v1.0 oauthLogin·getMe).
public struct RemoteAuthRepository: AuthRepository {
    private let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func signIn(with code: OAuthCode) async throws -> (accessToken: String, result: SignInResult) {
        do {
            let output = try await client.oauthLogin(
                path: .init(provider: Self.provider(code.provider)),
                body: .json(.init(code: code.code, redirectUri: code.redirectUri))
            )
            let body = try output.ok.body.json
            guard let token = body.accessToken, !token.isEmpty, let user = body.user else {
                throw DomainError.server(code: "INVALID_RESPONSE", message: nil)
            }
            let result = try SignInResult(
                user: Self.profile(user),
                isNewUser: body.isNewUser ?? false,
                needsOnboarding: body.needsOnboarding ?? false
            )
            return (token, result)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func me() async throws -> UserProfile {
        do {
            return try await Self.profile(client.getMe().ok.body.json)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    static func provider(_ provider: OAuthProvider) -> Operations.OauthLogin.Input.Path.ProviderPayload {
        switch provider {
        case .apple: .apple
        }
    }

    static func profile(_ dto: Components.Schemas.UserResponse) throws -> UserProfile {
        guard let id = dto.userId else { throw DomainError.server(code: "INVALID_RESPONSE", message: nil) }
        return UserProfile(id: id, nickname: dto.nickname ?? "", email: dto.email, jobGroup: dto.jobGroup?.value1.rawValue)
    }
}
