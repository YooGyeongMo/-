# 2026-10-26 — 로컬은 통과, CI는 실패: 린터 버전 차이

## 무슨 일
PR #111이 로컬 `swiftlint --strict` 0건이었는데 CI lint에서 `legacy_swiftui_aspect_ratio` 위반으로 실패했다.

## 원인
CI는 `brew install swiftlint`로 그날의 최신(0.65.1)을 받고, 로컬은 예전에 brew로 깐 0.59.1이었다. 새 버전에 추가된 규칙이 CI에서만 켜졌다.

## 고친 것
- `.mise.toml`에 `swiftlint = "0.65.1"` 고정. CI lint는 `mise-action`이 같은 버전을 설치하고 brew 설치 단계를 없앴다.
- 코드는 `aspectRatio(contentMode: .fit)` → `scaledToFit()`.

## 다음부터
도구 버전은 전부 `.mise.toml`(로컬·CI 공통)에서만 올린다. 올릴 때는 `mise exec -- swiftlint --strict`로 저장소 전체를 먼저 돌린다.
