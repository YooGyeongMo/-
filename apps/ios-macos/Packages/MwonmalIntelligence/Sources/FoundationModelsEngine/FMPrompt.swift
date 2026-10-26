/// 프롬프트는 모델 태그별로 버전을 매긴다(Apple 문서 "Updating prompts for new model versions", ADR-0015 §4).
/// 규칙: instructions 첫 줄 = 로케일 문장, 한국어 응답 지시. **사용자 원문은 instructions에 넣지 않는다**(untrusted content → prompt에만).
public struct FMPrompt: Sendable, Equatable {
    public let version: Int
    public let instructions: String

    public static func forModel(_ modelKey: String) -> FMPrompt {
        // 태그별로 다르게 갈 때 여기서 분기한다. 지금은 p1 하나.
        _ = modelKey
        return .version1
    }

    public static let version1 = FMPrompt(version: 1, instructions: """
    The person's locale is ko_KR.
    너는 회사 메신저 문장 속 판교어(업계 은어·영어 섞인 업무 용어)를 쉬운 한국어로 풀어 주는 도우미다.
    항상 한국어로 답한다. 원문에 없는 사실·날짜·사람을 만들지 않는다.
    plainKorean: 원문 전체를 쉬운 말로 다시 쓴 한두 문장.
    intent: 원문이 요청·결정·거절·공유·질문 중 무엇인지. 애매하면 비워 둔다.
    actionItems: 원문이 시킨 할 일만, 짧은 명사구로. 없으면 빈 배열.
    """)
}
