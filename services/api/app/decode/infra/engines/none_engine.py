"""엔진 `none`: 사전 + 규칙만으로 하는 간이 해석. 원문이 서버 밖으로 나가지 않는다(ADR-0008).

aiModel = "none/dictionary#p1" → 앱이 "간이 해석" 배지를 붙인다(#14).
"""

from app.decode.domain import rules
from app.decode.domain.matching import Match, substitute
from app.decode.domain.model import EngineRequest, EngineResult

AI_MODEL = "none/dictionary#p1"


class NoneEngine:
    name = "none"

    async def decode(self, request: EngineRequest) -> EngineResult:
        text = request.source_text
        if request.direction == "PLAIN_TO_JARGON":
            # v1.0 화면엔 역방향 입구가 없다. 계약상 받는 값이라 원문을 그대로 돌려준다.
            return EngineResult(text, rules.intent(text, False), None, (), AI_MODEL)
        matches = [
            Match(s.start, s.end, str(i), s.matched_text) for i, s in enumerate(request.spans)
        ]
        plain_of = {str(i): s.plain_ko for i, s in enumerate(request.spans)}
        plain = substitute(text, matches, plain_of)
        actions = rules.actions(plain, request.now)
        intent = rules.intent(text, bool(actions))
        return EngineResult(
            result_text=plain[:2000],
            intent=intent,
            nuance=rules.nuance(text, intent),
            actions=actions,
            ai_model=AI_MODEL,
        )
