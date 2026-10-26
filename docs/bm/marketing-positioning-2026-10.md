# 뭔말인교? — Apple 쪽 마케팅·핵심 기술·생산성 포지셔닝 리서치

> 작성 2026-10-26 · 근거: 저장소 `docs/`(PRD, bm/early-strategy, REQUIREMENTS, 16번 §0, ADR-0007/0008/0009/0013, 15번 T-D, 05 디자인시스템) + 웹 조사
> 표기: **[V]** = 1차(Apple 공식 등) 출처로 확인 · **[2V]** = 2차 출처 여럿이 일치 · **[U]** = 미확인/추정. 저장소는 수정하지 않았다.

---

## 0. 먼저 알아야 할 사실 6개 (마케팅 문구를 바꾸는 것들)

1. **"원문이 기기 밖으로 안 나간다"는 v1.0에선 사실이 아니다.** ADR-0008/0007 기준 v1.0 텍스트는 **내 서버(OCI)** 로 가서 사전·규칙으로 해석되고 기록으로 저장된다. 사용자가 옵트인하면 **Google Gemini 무료 티어**로도 간다. 오디오(v1.2)만 외부 STT 0(서버 whisper_local). → 쓸 수 있는 말은 "**추적 없음 · 광고 없음 · 외부 AI는 내가 켤 때만 · 기록은 언제든 삭제**"이다. "온디바이스", "기기 안에서만"은 쓰지 않는다.
2. **App Privacy 라벨은 "Data Not Collected"가 아니다.** Apple 정의상 서버에 저장하면 "수집"이다 [V](https://developer.apple.com/app-store/app-privacy-details/). v1.0 예상 라벨: *Data Linked to You* = 연락처(이메일, Sign in with Apple 릴레이 가능)·식별자(User ID)·사용자 콘텐츠(Other User Content/메시지 본문). *Data Used to Track You* = **없음**. Sentry·Amplitude가 백로그라 v1.0엔 진단·사용 데이터도 **없음** — 이게 실제 차별점이다(붙이는 순간 라벨이 바뀐다).
3. **App Store 심사 제출의 블로커: 계정 삭제.** `DELETE /users/me`가 v1.1 계약(12번 §13, RT-A-23). 계정을 만드는 앱은 앱 안에서 계정 삭제를 제공해야 한다(가이드라인 5.1.1(v)) [V](https://developer.apple.com/app-store/review/guidelines/). → **공개 출시(또는 사전 주문 등록) 전 반드시 구현**.
4. **iOS 27(2026-09 출시)에서 Foundation Models 판이 바뀌었다.** WWDC26: ① Private Cloud Compute(PCC) 서버 모델을 프레임워크에서 한 줄로 호출, **첫 다운로드 200만 미만 개발자는 클라우드 API 비용 없음**, 32K 컨텍스트, 사용자별 일일 한도(iCloud+면 더 높음), entitlement 필요 ② 온디바이스 모델 재구축, `contextSize`(예시 8192) ③ `LanguageModel` 프로토콜로 Gemini·Claude도 같은 세션 API ④ **Evaluations 프레임워크** [V](https://developer.apple.com/videos/play/wwdc2026/241/). ADR-0007의 "4096 토큰이라 회의록 불가" 전제는 낡았다. Apple Intelligence는 iOS 27에서 **한국어 지원**, 한국 지역 제한 없음 [V](https://support.apple.com/en-us/121115). 단 Foundation Models의 한국어 지원은 런타임 `supportedLanguages`로 확인해야 함 [U].
   → **제안(ADR 재검토 안건, 마케팅 문구 아님)**: v1.1~v1.2에 "Apple Intelligence 가능 기기 + iOS 27 = PCC/온디바이스 경로, 그 외 = 서버" 하이브리드. Gemini 무료 약관 문제(기밀 금지·인간 검토)를 피하면서 원가 0, 프라이버시 서사도 강해진다. 그 전엔 문구에 넣지 않는다.
5. **App Store 키워드에 상표·타사 앱 이름 금지**(2.3.7) [V]. "슬랙, 노션, 카카오톡, 파파고"는 키워드·부제·스크린샷 문구에 쓰지 않는다. 스크린샷 속 메신저도 가상의 UI로.
6. **한국 AI 기본법(2026-01-22 시행)**: 생성형 AI 제품·서비스는 이용자에게 사전 고지, 결과물 표시 의무. 과태료 최대 3,000만 원, 최소 1년 계도기간 [2V](https://www.pointdaily.co.kr/news/articleView.html?idxno=287029). → 결과 카드에 "AI 해석" 표기(간이 해석 배지와 같은 자리)와 온보딩 고지 1줄.

---

## 1. 한 줄 포지셔닝

| # | 후보 | 대상 | 해야 할 일(JTBD) | 장단점 |
|---|---|---|---|---|
| A | **"입사 첫 90일, 회사 말귀를 3초 만에 할 일로"** | IT 회사 신입·인턴·직무 전환자 | 받은 메시지에서 "그래서 내가 뭘 해야 하지?"를 빨리 알기 | 시기(온보딩)와 결과(할 일)가 분명. 공채 시즌 이벤트와 맞물림 |
| B | "판교어 해석기 — 쉬운 말·할 일·숨은 뜻" | IT 업계 전반 + 협업하는 비개발 직군 | 낯선 업계 말 해석 | 이름이 기억에 남지만 "번역기"로 읽혀 검색 3초짜리와 비교됨(PRD §1.1이 경계한 함정) |
| C | "모르는 말을 안 까먹게 만드는 업무 단어장" | 학습 동기 높은 신입 | 다시 검색하지 않기(간격 반복) | 근거(인출·분산 연습)가 강하지만 v1.1부터 가능, 교육 앱으로 보임 |

**추천: A.** 이름(뭔말인교?)이 재미를 맡고, 포지셔닝은 **생산성 결과(할 일)** 를 맡게 한다. B의 "판교어"는 이름 옆 수식어와 키워드로 쓰고, C는 v1.1 이후 "기억까지"라는 둘째 문장으로 붙인다.
> 메인 카피: **"회사 말귀, 3초 만에 할 일로."** 보조: "쉬운 말 · 내가 할 일 · 숨은 뜻을 한 번에. 모르는 말은 퇴근길에 복습까지."

경쟁 지형에서 빈 자리 (전부 직접 검증은 못 함 — 아래 표기):
| 대안 | 하는 일 | 못 하는 일 |
|---|---|---|
| 판벅(2024, 웹, 사전형) · AI 판교어 번역기(2025, 웹, LLM) [2V, 나무위키](https://namu.wiki/w/%ED%8C%90%EA%B5%90%EC%96%B4%EB%B2%88%EC%97%AD%EA%B8%B0) | 문장 → 일반어 | 할 일·기한·의도 추출 없음, 복습 없음, 네이티브 앱 아님 |
| 클로바노트·다글로·티로 [2V](https://wikidocs.net/blog/@openwiki/23917/) | 회의 받아쓰기·요약·액션아이템 | 용어 해석·뉘앙스·학습 없음. **v1.2 회의 기능은 이들과 정면 경쟁 → 차별점은 "회의 안의 판교어"** |
| ChatGPT/Gemini/Notion AI 등 범용 LLM | 물어보면 다 해줌 | 매번 프롬프트, 회사 기밀 붙여넣기 부담, 기록·복습 없음 |
| Apple 글쓰기 도구 → iOS 27 "Write with Siri" [2V](https://9to5mac.com/?p=1057818) | 시스템 전역 재작성·요약 | 한국어 범위 불확실 [U], 할 일·의도·용어 학습 없음. **"OS가 공짜로 해주는 것"과 겹치지 않게 "쉬운 말로 바꾸기" 단독으로는 홍보 금지** |
| 파파고·DeepL | 언어 간 번역 | 한국어→한국어(혼용어) 해석은 목적 밖 |

---

## 2. 핵심 기술 — 두 관객에게 다르게

### 2-1. 사용자에게 보이는 가치 (스토어·SNS 문구)
1. **3초 해석**: 붙여넣기 한 번 → 쉬운 말 / 🎯 내가 할 일(+기한 힌트) / 💭 숨은 뜻(요청·결정 통보·완곡한 거절·단순 공유·질문 5종 + 대응 팁).
2. **원문 위 형광펜**: 모르는 말 위치를 정확히 칠해 줌(탭하면 뜻).
3. **기밀 걱정 덜기**: 기본은 사전·규칙 해석, 외부 AI는 내가 켤 때만, 추적·광고 없음, 기록 삭제.
4. (v1.1) **안 까먹게**: 담은 말만 퇴근길 5분 복습, 판교 등급 5단계.
5. (v1.2) **회의 속 판교어**: 녹음 → 받아쓰기 → 할 일. 오디오는 외부 STT로 안 보냄, 30일 뒤 자동 삭제.
6. (v1.3~1.4) **iPhone·iPad·Mac 같은 계정**: 회의실 iPad, 자리 Mac, 퇴근길 iPhone.

### 2-2. 채용 포트폴리오로 보이는 기술 (README·블로그·면접)
| 기술 | 증거물(저장소) | 면접 한 줄 |
|---|---|---|
| **프라이버시 우선 AI 라우팅** — 옵트인 헤더(`X-Mw-AI-Consent`), prod 사슬 `gemini_free → none`, 유료 키 존재 시 기동 실패 assert, 원문 무유출 **카나리 테스트** | ADR-0008, REQ-33 | "약관과 기밀 요구가 충돌할 때 코드·테스트로 닫았다" |
| **평가셋 기반 엔진 선택** — 합성 200문장, 스팬 F1·의도 정확도·LLM-judge(Spearman≥0.7), Foundation Models 80% 게이트 | ADR-0007, `eval/` | "모델은 감이 아니라 점수표로 바꾼다" (+iOS 27 Evaluations 프레임워크로 이식하면 Apple 문법으로도 설명 가능) |
| **용어 스팬 탐지 + 하이라이트 인덱스** — 서버 trie, 유니코드 스칼라 인덱스, Swift·Python 공유 테스트 벡터, `AttributedString` 링크 | `packages/test-vectors/`, `JargonText` | "한글 인덱스 오프셋을 두 언어에서 같게" — 작지만 깊은 문제 |
| **MAU당 원가 계산기** — 무료 한도(RPD·피크 RPM) 반영, 손익분기 역산, 레드팀 산식 오류 3개 수정 | ADR-0009, `eval/cost_model.py` | "BM을 코드로 검증하는 엔지니어" |
| **멀티플랫폼 SwiftUI + Tuist 모듈** — Domain watchOS 데스티네이션, `AdaptiveRoot`(h·v regular), iOS 17 게이트 3곳·폴백 7개, Motion 모듈·린트 | ADR-0001/5/6/12 | "iPhone→iPad→Mac를 루트 2벌로" |
| **의사결정 문화** — ADR 14개, 역할별 협의체 + 레드팀, 롤링 릴리스 | `docs/adr`, `docs/council` | 토스·보이저엑스류 면접에서 가장 차별화되는 자산 |
| (권장 추가) **Apple 네이티브 통합** — Share Extension·App Intents·Spotlight·위젯 | 아직 없음(§3 참고) | 에디터·면접관 모두에게 "Apple을 잘 아는 개발자" 신호 |

**한 문장 요약(포트폴리오용)**: "개인 정보와 AI 원가 사이에서 엔진을 점수표로 고르고, 그 결정을 iPhone·iPad·Mac 네이티브 경험으로 옮긴 1인 개발 제품."

---

## 3. 생산성 앱으로서의 콘셉트

카테고리: **주 = 생산성(Productivity)**, **부 = 교육(Education)**. Apple 정의: 생산성 = "특정 과정·작업을 더 정리되고 효율적으로", 번역도 생산성 예시에 포함. 교육 = 어휘·언어 학습 [V](https://developer.apple.com/app-store/categories/). 비즈니스는 "사업 운영·협업" 쪽이라 개인 사용자 앱엔 부적합. 참조(사전)로 가면 "번역기·사전" 비교에 갇힌다.

### 3-1. 하루 흐름과 진입점
| 순간 | 지금(계획) | Apple 네이티브로 만들면 | 시점 제안 |
|---|---|---|---|
| 메신저에서 이상한 문장 받음 | 앱 열기 → `PasteButton`(v1.0), 클립보드 배너 | **Share Extension**(공유 시트 "뭔말인교로 해석") — T-D2에서 v1.1 확정 | v1.1 |
| 손 안 쓰고 빨리 | — | **App Intents "판교어 해석"** → 단축어·Siri·Spotlight·동작 버튼. 결과 스니펫 뷰 | v1.1 (0.5~1일) |
| 예전에 본 말 다시 찾기 | 홈 기록 목록 | **Spotlight 색인**(Core Spotlight, 용어·카드), 앱 내 검색 | v1.1~1.2 |
| 회의 중 | v1.2 녹음, 인앱 ● 배너 | **Live Activity**(녹음 경과·정지) — T-D1에서 v1.1로 밀림 | v1.2 |
| 퇴근길 | 복습 알림(길게 눌러 바로 복습) | **위젯**(오늘 복습 N장·스트릭), 잠금화면 위젯 | v1.1~1.2 |
| 자리(Mac) | v1.4 macOS | 메뉴 막대·전역 단축키로 클립보드 해석, 서비스 메뉴 | v1.4 |
| iPad 회의실 | v1.3 사이드바 | Split View에서 메신저 옆에 띄워 쓰기 | v1.3 |

v1.0은 손대지 않는다(60h 버퍼 하루뿐). App Intents는 에디터가 실제로 보는 "새 기술 활용"(Innovation 기준) 항목이라 v1.1의 Share Extension과 함께 넣는 게 투자 대비 효과가 가장 크다.

### 3-2. 측정 가능한 결과 (스토어·인터뷰에 쓰려면 실측 필요)
- **해석 1건 소요 시간**(붙여넣기→결과 표시 p50 ≤ 3초) — 서버 로그로 바로 측정 가능.
- **할 일 체크율**: 해석에서 나온 할 일 중 체크된 비율(`action_checked`).
- **재검색 감소 대리 지표**: 같은 용어 재해석 횟수 감소, 카드 7일 회상률(v1.1).
- **베타 설문 1문항**: "이번 주 메시지 의도를 잘못 이해한 일이 줄었다"(5점).
> 실측 전에는 "3초 만에"를 목표 문구로만 쓰고, 수치 주장("N% 빨라짐")은 하지 않는다(가이드라인: 검증 불가 주장 금지 — 인앱 이벤트 문서도 "the best", "#1" 금지 [V](https://developer.apple.com/app-store/in-app-events/)).

---

## 4. Apple 마케팅 계획 (릴리스 일정에 맞춤)

### 4-1. 확인된 규칙 요약
| 항목 | 값 | 출처 |
|---|---|---|
| 앱 이름 / 부제 | 각 30자 | [V](https://developer.apple.com/app-store/product-page/) |
| 키워드 | **100자**(쉼표 구분, 공백 없이), 복수형·카테고리명·"앱"·중복 금지. 과거 "100바이트"였다가 2013년 문자 기준으로 바뀜 [2V](https://www.ibabbleon.com/copywriter-translator/2013/06/apple-finally-allows-100-characters-of-keywords-in-all-languages-of-the-app-store/) → ASC 입력란 카운터로 최종 확인 | [V] |
| 홍보 문구 | 170자, 검색 순위에 영향 없음, 심사 없이 수시 변경 | [V] |
| 스크린샷 / 미리보기 | 최대 10장 / 3개·각 30초 | [V] |
| 맞춤 제품 페이지 | 최대 70개, 스크린샷·홍보 문구·미리보기 변경, 딥링크(iOS 18+), **키워드 지정 가능** | [V](https://developer.apple.com/app-store/custom-product-pages/) |
| 제품 페이지 최적화 | 동시 1개 테스트, 처리안 3개, 최대 90일, 아이콘 테스트는 바이너리에 아이콘 포함 | [V](https://developer.apple.com/app-store/product-page-optimization/) |
| 인앱 이벤트 | 이름 30자·짧은 설명 50자·긴 설명 120자, 최대 31일, 시작 14일 전부터 노출, 승인 15개/게시 10개, 가격 표기 시 거절 | [V](https://developer.apple.com/app-store/in-app-events/) |
| 피처링 추천 | ASC > 앱 > Featuring > Nominations. 유형 3개(새 콘텐츠 / 앱 개선 / **앱 출시·사전 주문**). **최소 3주 전**(ASC 도움말), 넓은 고려엔 **최대 3개월 전** 권장. 보조 URL 5개(TestFlight 공개 링크 가능), 인앱 이벤트 첨부 | [V](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring) · [V](https://developer.apple.com/app-store/getting-featured/) |
| 에디터가 보는 것 | UX, UI 디자인, 혁신(새 기술), 독창성, **접근성**, **현지화**, 제품 페이지(스크린샷·평점) | [V] 위 링크 |
| Small Business Program | 수수료 15%(구독 2년차 10%), 전년도 수익 100만 USD 이하 | [V](https://developer.apple.com/app-store/small-business-program/) |
| Apple Ads | Basic = 설치당 과금(CPI), 신규 100 USD 크레딧 [V](https://ads.apple.com/app-store/basic). 한국은 2018년부터 지원 [2V](https://techcrunch.com/2018/07/25/apples-search-ads-expand-to-six-more-markets-in-europe-and-asia) — 현재 국가 목록은 콘솔에서 확인 [U] |
| Apple Design Awards 2026 | 6개 부문: Delight and Fun · Inclusivity · Innovation · Interaction · Social Impact · Visuals and Graphics. 2026-06-02 발표 | [V](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/) |

### 4-2. 일정 (추천안)
ADR-0008·early-strategy의 "베타 ≤ 50명 → 대기열 → 유료 실험" 순서를 지키면서 **대기열을 App Store 사전 주문으로 대체**한다(이메일 PII 수집 불필요, 사전 주문은 피처링 대상 [V]). 출시일은 **신입·인턴 입사 시즌(1~3월) 직전**에 맞춘다.

| 날짜 | 할 일 | 비고 |
|---|---|---|
| 11/18(수) Day 18 | ASC 레코드, 개인정보 라벨, **Small Business Program 신청**, 개인정보 처리방침 URL | 이미 계획됨 + SBP 1줄 추가 |
| **11/20(금)** | v1.0 TestFlight 내부, 외부 베타 심사 제출 | ADR-0013 |
| 11/23~12/18 | 외부 TestFlight(공개 링크, 인원 제한 50). 측정: p50 지연, 옵트인율, 할 일 체크율 | 베타 피드백 = 스크린샷 문장 원천 |
| 12/3(목) | v1.1 복습 (+ **Share Extension, App Intents, 계정 삭제** 넣기 권장) | 계정 삭제가 공개 출시 블로커 |
| 12/7~12/11 | 스크린샷·문구 제작(2~3h × 3일), 접근성(VoiceOver·Dynamic Type) 점검 | 에디터 기준 "접근성" |
| **12/14(월)** | 앱 심사 제출 → 승인되면 **사전 주문 공개**(출시일 2027-02-22) | 사전 주문은 승인 후 최대 180일 전부터 가능 [U, ASC에서 확인] |
| **12/14(월)** | 피처링 추천 ① **App Launch**(출시일 2/22, 10주 전) — 보조 자료: TestFlight 링크, 데모 영상, 설계 문서 1장 | "3개월 전" 권장에 가깝게 |
| 12/24(목) | v1.2 회의 | |
| 1/8(금) · 1/19(화) | v1.3 iPad · v1.4 macOS | 출시 버전 = iPhone·iPad·Mac **유니버설 구매** |
| 1/25(월) | 피처링 추천 ② **App Enhancements**(Mac·iPad 동시, 회의 받아쓰기) — 출시 4주 전 | |
| 2/8(월) 전후 | 인앱 이벤트 ① 승인 받기(시작 14일 전 노출) | 설 연휴(2027-02-06 전후 [U]) 피함 |
| **2/22(월)** | **App Store 공개 출시(한국 스토어 우선)** | 3월 입사 시즌 2주 전 |
| 3/2~3/31 | 인앱 이벤트 ① "신입 첫 달 판교어 챌린지"(Challenge, 31일) | |
| 3월 이후 | 평점 ≥ 4.5·리뷰 10개 이후 Apple Ads Basic | §4-6 |

> 더 빠른 대안: v1.1 승인 직후 12월 중순 바로 공개 출시. 평점이 일찍 쌓이지만 베타 50명 원칙·Gemini 무료 한도(ADR-0009 "무료 한도 소진 MAU")와 충돌할 수 있어 비추천.

### 4-3. 제품 페이지 문구 (초안, 글자 수 계산 완료)
- **이름(13자)**: `뭔말인교? 판교어 해석기`
- **부제(18자)**: `회의·메신저 말을 할 일로 바꿔요` (대안 17자: `회사 말귀, 3초 만에 할 일로`)
- **키워드(91자)** — 이름·부제 단어(판교어·해석·회의·할 일)는 중복이라 뺌, 상표 0:
  `직장용어,회사용어,업무용어,신입사원,인턴,온보딩,회의록,할일,용어사전,은어,뜻풀이,쉬운말,뉘앙스,얼라인,팔로업,싱크,단어장,복습,IT용어,스타트업,완곡어법,업무지시`
  (ASC가 바이트로 셀 경우의 축약본 32자/80바이트: `직장용어,회사용어,신입,온보딩,할일,은어,뜻,쉬운말,얼라인`)
- **홍보 문구(170자 이내)**: "스코프 아웃, R&R, 얼라인… 받은 말을 붙여 넣으면 쉬운 말·내가 할 일·숨은 뜻으로 풀어 드려요. 외부 AI는 내가 켤 때만 써요."
- **설명 첫 3줄**: ① 문제("단어는 검색되지만, 그래서 뭘 하라는 건지는 안 나와요") ② 해결 3요소 ③ 신뢰(추적 없음·외부 AI 옵트인·기록 삭제). 이후 기능 목록, "iPhone, iPad, Mac에서 쓸 수 있어요"(Apple 표기 규칙: "for iPhone"·"works with", OS 이름 지양 [V](https://developer.apple.com/app-store/marketing/guidelines/)).
- **맞춤 제품 페이지 2개**(v1.2 이후): ① "신입 온보딩"(키워드: 신입사원·온보딩) ② "회의 받아쓰기"(키워드: 회의록, 딥링크 → 새 회의).

### 4-4. 스크린샷 6장 스토리보드 (iPhone 6.9" 기준, 문구는 기기 옆·위에)
| # | 헤드라인 | 화면 | 메시지 |
|---|---|---|---|
| 1 | **회사 말귀, 3초 만에 할 일로** | 대표 시나리오 원문 → 결과 카드 전체 | 핵심 가치 한 장 |
| 2 | 모르는 말엔 형광펜 | 원문 위 `--sun` 하이라이트 + 용어 시트 | 스팬 탐지(기술 신호) |
| 3 | 🎯 그래서 내가 할 일은 | 할 일 2개 + 기한 힌트 + 체크 | 생산성 |
| 4 | 💭 "챌린지가 있네요" = 거절이에요 | 의도 배지 + 대응 팁 | 독창성(검색으로 안 되는 것) |
| 5 | 외부 AI는 내가 켤 때만 | 설정 옵트인 토글 + 고지문, "추적 없음" | 신뢰 |
| 6 | (v1.1~) 퇴근길 5분, 안 까먹게 | 복습 카드 앞/뒤 + 등급 사다리 | 기억 루프 |
v1.3 이후 7~8장: iPad 사이드바, Mac 창. 규칙: 가상 데이터, 실제 메신저 UI·로고 금지, Apple 기기 프레임은 Apple 제공 이미지 그대로, 홈 화면 노출 금지(위젯 예외) [V].
**미리보기 영상(15~20초)**: 앱이 열린 상태로 시작 → 붙여넣기 → 결과 카드 펼침 → 카드 담기. 전환은 페이드만 [V].

### 4-5. 인앱 이벤트 (릴리스마다 하나)
| 시점 | 배지 | 이름(≤30) | 짧은 설명(≤50) |
|---|---|---|---|
| v1.1 업데이트 후 (출시 후 운영) | Major Update | 퇴근길 복습 시작 | 오늘 해석한 말, 5분이면 안 까먹어요 |
| 출시 3월 | Challenge | 신입 첫 달 판교어 챌린지 | 30일 동안 매일 한 문장, 판교 등급 올리기 |
| v1.2 | Major Update | 회의 속 판교어 받아쓰기 | 녹음하면 할 일까지 정리해 드려요 |
| v1.3/1.4 | Major Update | 이제 iPad와 Mac에서도 | 회의실 iPad, 자리 Mac, 퇴근길 iPhone |
| 7월·9월(인턴·하반기 입사) | Special Event | 인턴 첫 주 생존 단어 30 | 첫 주에 가장 많이 듣는 말 모음 |
(인앱 이벤트는 iPhone·iPad만 [V]. 가격·"최고" 표현 금지.)

### 4-6. Apple Ads (예산 0~소액)
- **출시 전·직후 0원**: 오가닉 키워드·피처링·평점 먼저. 평점 요청은 `requestReview`를 **할 일 체크 직후** 같은 긍정 순간에.
- **평점 ≥ 4.5 + 리뷰 10개 이후**: Basic 신규 크레딧 100 USD로 2~4주, 설치당 최대 단가 상한을 낮게. 효과 보이면 월 10만 원 상한.
- 측정: 설치→첫 해석 전환율(서버 기준). Advanced로 가면 정확 일치 `판교어`·`직장용어`, 브랜드 키워드 방어만. 경쟁 앱 이름 입찰은 하지 않는다.

### 4-7. 해서는 안 되는 것 (상표·문구)
- "Apple Intelligence"를 앱 이름·아이콘·이미지에 넣기, "Apple이 인증/제휴" 암시, 동사·복수·소유격 사용("Apple Intelligence로 하다" X) [V](https://apple.com/legal/intellectual-property/trademark/appletmlist.html). 실제로 쓸 때만 설명문에 "Apple Intelligence를 지원하는 기기에서 …" 정도.
- **지금은** "온디바이스 AI", "Apple Intelligence 기반"이라고 쓰지 않는다(v1.0 사용자 경로에 없음, ADR-0007 §4-3 게이트 통과 전).
- 키워드·부제에 슬랙·카카오톡·노션·파파고·ChatGPT. "#1·최고·완벽 번역" 같은 검증 불가 표현.
- "iPhone 앱 뭔말인교" 어순(→ "뭔말인교 for iPhone"), 자체 제작 한국어 App Store 배지(Apple 제공 한국어 배지만, "App Store"는 영어 유지) [V].
- 판교 사람을 놀리는 톤(디자인시스템 보이스 "같이 웃는다" 유지) — 2.3.8·1.1 쪽 리스크도 줄어든다.

---

## 5. 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| 계정 삭제 미구현 | 공개 심사 거절(5.1.1(v)) | v1.1에 `DELETE /users/me` + A-09 항목 |
| 외부 AI 동의 UI가 약함 | 5.1.2(i) "제3자 AI 공유는 명확히 고지·명시적 동의" [V] | 정책 링크만으로 부족(2V) → 이미 계획한 고지 시트 + 기본 OFF 유지, 동의 문구에 "Google" 명시 |
| 1.2(UGC/AI 콘텐츠 생성) 지적 | 신고·필터 요구 가능 | 결과 카드에 "해석이 이상해요" 신고 버튼(평가셋 신고 흐름과 겸용), 연락처 공개 |
| Apple Intelligence 경로 | iPhone 15 Pro·16 이상만, 기기·Siri 언어 일치 필요 [V]; FM 한국어·PCC 한도·entitlement 미확인 [U] | 마케팅 전제에 넣지 않음. 들어가도 "지원 기기에서 더 빠르게" 부가 문구로만 |
| FM 이용 정책 | "고용 등 고위험 영역에서 사람 감독 없이 중대한 결정" 금지 [V](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/) | "인사평가·채용 판단" 쓰임새로 홍보하지 않음. 뉘앙스는 "참고용 해석" 문구 |
| AI 기본법 고지 | 과태료(계도기간 후) | 온보딩 고지 + 결과 "AI 해석" 표시 |
| 해석 오류가 업무 실수로 | 별점·신뢰 하락 | 의도 판정 "~일 수 있어요" 어조, 원문 항상 같이 보여 주기 |
| Gemini 무료 한도·약관 변경 | 옵트인 사용자 품질 하락 | ADR-0008대로 `none` 강등 + 배지. 중기적으로 PCC 하이브리드 검토 |
| 경쟁자 기능 흡수(회의록 앱의 용어 설명, iOS 27 Write with Siri) | 차별점 약화 | 할 일+의도+복습 "한 화면"과 프라이버시를 계속 앞에 |
| 1인 시간 부족 | 마케팅이 개발을 잠식 | 아래 체크리스트를 주 2~3h로 묶음, 개발 Day에 섞지 않기(16번 §0 원칙과 동일) |

---

## 6. 1페이지 체크리스트 (날짜순)

- [ ] **11/18** ASC: 앱 레코드·카테고리(생산성/교육)·개인정보 라벨(Linked: 연락처·식별자·사용자 콘텐츠 / Tracking 없음)·처리방침 URL·**Small Business Program 신청**
- [ ] **11/20** TestFlight 내부 + 외부 베타 심사 제출, 공개 링크 50명 제한
- [ ] **11/23~12/18** 베타 지표 3개(p50 지연, 옵트인율, 할 일 체크율) 기록 → 스크린샷 문구에 반영
- [ ] **12/3** v1.1에 계정 삭제 + Share Extension + App Intents "판교어 해석" + 결과 신고 버튼 + "AI 해석" 표기
- [ ] **12/7~11** 스크린샷 6장·미리보기 20초·이름/부제/키워드/홍보 문구 입력(ASC 카운터로 키워드 길이 확인), VoiceOver·Dynamic Type 점검
- [ ] **12/14** 심사 제출 → 사전 주문(출시 2/22) 공개 / **피처링 추천 ① App Launch** 제출(보조 URL: TestFlight·데모 영상·아키텍처 그림)
- [ ] **12월 말** ADR 안건: iOS 27 PCC·온디바이스 하이브리드 + Evaluations 프레임워크 (마케팅 문구는 결정 후)
- [ ] **1/19** v1.4 완료 → iPad·Mac 스크린샷 추가
- [ ] **1/25** **피처링 추천 ② App Enhancements**(유니버설·회의)
- [ ] **2/8 전후** 인앱 이벤트 "신입 첫 달 판교어 챌린지" 승인(3/2 시작, 2/16부터 노출)
- [ ] **2/22** 공개 출시, 평점 요청 타이밍 = 할 일 체크 직후
- [ ] **3월** 평점 ≥ 4.5·리뷰 10개 → Apple Ads Basic 100 USD 크레딧 실험
- [ ] **매 릴리스** 인앱 이벤트 1개 + 피처링 추천(새 콘텐츠/앱 개선) 최소 3주 전
- [ ] **2027-02~03** ADA 2027 노리면 Inclusivity(접근성)·Interaction(공유 시트·App Intents) 쪽 근거를 쌓아 두기 [U: 2027 접수 방식 미확인]

### 출처 모음
Apple: [Getting featured](https://developer.apple.com/app-store/getting-featured/) · [Nominate (ASC Help)](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring) · [Product page](https://developer.apple.com/app-store/product-page/) · [Custom product pages](https://developer.apple.com/app-store/custom-product-pages/) · [PPO](https://developer.apple.com/app-store/product-page-optimization/) · [In-App Events](https://developer.apple.com/app-store/in-app-events/) · [Categories](https://developer.apple.com/app-store/categories/) · [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) · [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/) · [Trademark list](https://apple.com/legal/intellectual-property/trademark/appletmlist.html) · [Small Business Program](https://developer.apple.com/app-store/small-business-program/) · [Apple Ads Basic](https://ads.apple.com/app-store/basic) · [Apple Intelligence 지원(언어·기기)](https://support.apple.com/en-us/121115) · [WWDC26 Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/) · [FM 이용 정책](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/) · [ADA 2026](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/)
기타(2차): [키워드 바이트→문자 변경](https://www.ibabbleon.com/copywriter-translator/2013/06/apple-finally-allows-100-characters-of-keywords-in-all-languages-of-the-app-store/) · [Search Ads 한국 확장 2018](https://techcrunch.com/2018/07/25/apples-search-ads-expand-to-six-more-markets-in-europe-and-asia) · [판교어번역기(나무위키)](https://namu.wiki/w/%ED%8C%90%EA%B5%90%EC%96%B4%EB%B2%88%EC%97%AD%EA%B8%B0) · [회의록 AI 비교 2026](https://wikidocs.net/blog/@openwiki/23917/) · [AI 기본법 시행](https://www.pointdaily.co.kr/news/articleView.html?idxno=287029) · [iOS 27 Write with Siri](https://9to5mac.com/?p=1057818) · [PCC 무료 조건(WWDC Notes)](https://wwdcnotes.com/documentation/wwdc26-319-build-with-the-new-apple-foundation-model-on-private-cloud-compute/)
