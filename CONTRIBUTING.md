# 기여 규칙 (혼자여도 지킨다)

## 이슈
- 제목 `[S1][app] 로그인 화면 S-01` — `[스프린트][영역]`. 영역: app, server, contracts, infra, docs, qa.
- 템플릿 필드 전부 채운다: 목적 / 범위 / 완료 기준(체크박스) / 트레이드오프(없으면 "없음") / 관련 문서 / 화면 ID / 예상 시간.
- 라벨: `area:*`, `type:*`, `sprint:S*`, `size:*`, `blocked`.

## 브랜치·커밋
- 브랜치 `s1/app-signin-#23`.
- 커밋 `feat(app/Presentation): S-01 로그인 화면 (#23)`. 본문: 왜 / 무엇 / 테스트. 트레이드오프는 `ADR: 0007`.
- 타입: feat, fix, chore, docs, test, refactor, ci, adr. 스코프: `app/<모듈>`, `server/<서비스>`, `contracts`, `infra`, `docs`.
- AI 공동 저자 트레일러를 넣지 않는다.

## PR
- 제목 = squash 커밋 제목. 템플릿 전부 채움. `Closes #n`.
- 화면 변경은 스크린샷·녹화 필수. 계약 변경은 앱 생성 코드 컴파일 로그 첨부.
- 셀프 리뷰 코멘트 1개 이상. CI 초록 후 squash merge.

## ADR
- `docs/adr/NNNN-제목.md`, 템플릿 `0000-template.md`. 트레이드오프가 있었으면 크기와 무관하게 쓴다.

## 일별 로그
- `docs/log/YYYY-MM-DD.md` 5줄: 한 것 / 막힌 것 / 내일 / 결정·발견.

## 도구
- `mise install` 한 번(tuist, swiftformat, uv, python). 린트: `make lint`. 테스트: `make test`.
