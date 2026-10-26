import Domain
import Foundation
import MwonmalAPI

/// 생성 클라이언트·전송 계층 에러 → DomainError. 서버 본문이나 기술 메시지는 화면에 넘기지 않는다.
enum DomainErrorMapping {
    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
    ]

    static func map(_ error: any Error) -> DomainError {
        if let domain = error as? DomainError {
            return domain
        }
        let cause = APIErrorCause.root(of: error)
        if cause is CancellationError {
            return .cancelled
        }
        if let url = cause as? URLError {
            if url.code == .cancelled {
                return .cancelled
            }
            return offlineCodes.contains(url.code) ? .offline : .unknown
        }
        if let server = MwonmalServerError.unwrap(cause) {
            switch server.code {
            case "OAUTH_CODE_INVALID": return .signInFailed(message: server.message)
            case "EMAIL_ALREADY_REGISTERED": return .emailAlreadyRegistered(message: server.message)
            case "UNAUTHORIZED": return .unauthorized
            default: return .server(code: server.code, message: server.message)
            }
        }
        return .unknown
    }
}
