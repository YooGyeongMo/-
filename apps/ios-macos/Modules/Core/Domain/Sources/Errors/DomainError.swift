/// 화면이 다루는 에러. 서버 코드·전송 계층 에러는 Data가 여기로 바꾼다(12번 §5).
/// `message`는 서버가 준 사용자용 문구(계약 Error.message)이고, 없으면 화면이 기본 문구를 쓴다.
public enum DomainError: Error, Sendable, Equatable {
    /// 사용자가 로그인 창을 닫았다. 에러 문구를 보여 주지 않는다.
    case cancelled
    /// 제공자 code가 유효하지 않음(OAUTH_CODE_INVALID). 로그인 화면 에러.
    case signInFailed(message: String?)
    /// 다른 제공자로 이미 가입한 이메일(EMAIL_ALREADY_REGISTERED).
    case emailAlreadyRegistered(message: String?)
    /// 토큰 만료·무효(UNAUTHORIZED). 재로그인.
    case unauthorized
    /// 네트워크에 닿지 못함.
    case offline
    /// 그 밖의 서버 에러.
    case server(code: String, message: String?)
    case unknown
}
