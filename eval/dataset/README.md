# 평가셋 (FD-5 / ADR-0007)

`v0_50.jsonl`(S2 Day 11) → `v1_200.jsonl`(S2 끝). **합성 + 검수, 실사용자 문장 0.** 라우팅 결정(REQ-10~13)의 유일한 근거.

## 200문장 구성

| 축 | 값 | 비율 |
|---|---|---|
| `direction` (`TranslationDirection`) | `JARGON_TO_PLAIN` 160 / `PLAIN_TO_JARGON` 40 | 80 / 20 |
| `sourceType` (`SourceType`) | `MESSAGE`(≤500자) 170 / `MEETING_NOTE`(1,000~5,000자) 30 | 85 / 15 |
| 용어 밀도 | 0개(청정 한국어) 20 · 1~2개 100 · 3개+ 80 | 검출 F1 의 재현율 하한용 |
| 의도 (`IntentType`) | REQUEST 60 · DECISION 40 · DECLINE 40 · SHARE 40 · QUESTION 20 | DECLINE(완곡 거절)이 숨은 뜻 채점의 핵심 |
| 할 일 | 있음 90 / 없음 110 | 없음 문장에서 지어내는지(정밀도) 본다 |
| 사전 밖 신규 용어 | 30문장에 1개 이상 (`termId: null`) | 사전 우선 + AI 신규 용어 경로 |
| 함정 | 동음이의·영문 약어 소문자·띄어쓰기 변형 20 | 스팬 인덱스 정확도 |

작성: 판교어 사전 시드 + 템플릿 합성 → 2인 검수(용어 스팬·의도·할 일) → 검수자 불일치는 `meta.disputed = true` 로 두고 채점에서 제외.

## 한 줄(JSONL) 형식

```json
{"id": "v1-0001",
 "direction": "JARGON_TO_PLAIN",
 "sourceType": "MESSAGE",
 "sourceText": "이번 스프린트 얼라인 한번 하고 다음 주에 킥오프 밀죠.",
 "gold": {
   "resultText": "이번 스프린트 방향을 맞추고 다음 주에 시작 회의를 하자는 뜻입니다.",
   "jargonCount": 2,
   "intentType": "DECISION",
   "nuance": {"note": "\"밀죠\"는 제안형이지만 이미 결정된 일정을 통보하는 표현입니다.", "tip": "되묻기보다 일정만 확인하는 편이 안전합니다."},
   "actionItems": [{"actionText": "다음 주 킥오프 일정 확인", "dueHint": "다음 주"}],
   "detectedTerms": [
     {"termId": 3, "termKo": "얼라인", "plainKo": "방향 맞추기", "matchedText": "얼라인", "startIndex": 8, "endIndex": 11},
     {"termId": null, "termKo": "킥오프", "plainKo": "시작 회의", "matchedText": "킥오프", "startIndex": 24, "endIndex": 27}
   ]
 },
 "meta": {"source": "synthetic", "reviewed_by": ["a", "b"], "disputed": false, "tags": ["decline-soft"]}}
```

`gold` 는 `contracts/openapi.yml` `components.schemas.TranslationResponse` 의 **AI 생성 부분집합**이다. 필드명은 yml 그대로:

| gold 키 | yml 원본 | 비고 |
|---|---|---|
| `resultText` | `TranslationResponse.resultText` | 쉬운 말 전체 |
| `jargonCount` | `TranslationResponse.jargonCount` | `detectedTerms` 길이와 같아야 함 |
| `intentType` | `IntentType` enum: `REQUEST\|DECISION\|DECLINE\|SHARE\|QUESTION` 또는 `null` | |
| `nuance` | `NuanceInfo` — `note`, `tip` (`confidence` 는 gold 에 없음) 또는 `null` | |
| `actionItems[]` | `ActionItem` — `actionText`, `dueHint` 만 (`actionId`·`dueAt`·`isChecked`·`alertEnabled`·`checkedAt` 는 서버 생성 → 제외) | |
| `detectedTerms[]` | `DetectedTerm` — `termId`, `termKo`, `plainKo`, `matchedText`, `startIndex`, `endIndex` (`confidence`·`inMyCards` 제외) | 인덱스는 `sourceText` 기준 0-시작·끝 미포함 |

`gold` 에 **없는** 것: `translationId`·`projectId`·`projectName`·`meetingId`·`meetingTitle`·`inputSource`·`aiModel`·`latencyMs`·`createdAt`(서버 메타).

## 채점 (eval/run.py)

1. 용어 스팬 F1 — `detectedTerms[].startIndex/endIndex` 정확 일치.
2. 쉬운 말·숨은 뜻 — LLM-judge 5점 (루브릭은 `eval/scores/`에, judge 어댑터 없이는 실행 안 됨).
3. 할 일 — `actionText` 정규화 후 정확 일치율 + 집합 F1.

점수표는 `eval/scores/*.md` 에 트랙 4행 × (점수·p50 지연·원가·프라이버시) 로 남기고 ADR-0007 에 링크한다.
