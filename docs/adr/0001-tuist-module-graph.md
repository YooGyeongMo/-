# ADR-0001: iOS·macOS 프로젝트는 Tuist로 생성하고 공통 코드는 모듈(프레임워크)로 나눈다

- 상태: 채택 (2026-09-19)
- 관련: 설계 12번 §0·§1-3, 15번 T-C4, 이슈 #2
- 2026-09-21 개정: Domain은 watchOS 10.0 데스티네이션 포함(ADR-0010) — `Domain`·`DomainTests`만 `.appleWatch` 추가, 의존성 0 확인 후. 다른 모듈은 그대로.

## 맥락
앱 타깃 2개(iOS, macOS), 공용 모듈 8개, Catalog 앱, 테스트 타깃이 한 그래프에 있어야 한다. 반복되는 UI·네트워크·도메인 코드를 SDK처럼 재사용하고 싶다.

## 선택지
| 선택지 | 장점 | 단점 |
|---|---|---|
| SPM 단일 패키지 + 손으로 만든 Xcode 프로젝트 | 표준 도구만 | 앱 타깃·스킴·설정을 pbxproj로 관리, 머지 충돌, 모듈 캐시 없음 |
| Tuist(프로젝트 생성) + SPM(외부 의존성) | 그래프를 코드로, 모듈 캐시(`tuist cache`), 스킴·설정 자동, pbxproj 커밋 안 함 | 도구 하나 더, 생성 단계 |
| XcodeGen | 가볍다 | 캐시 없음, 모듈 그래프 검사 없음 |

## 결정
Tuist. 모듈은 정적 프레임워크 타깃: Domain, Data, MwonmalAPI, Platform, MwonmalUI, Presentation, Navigation, Composition. 외부 의존성은 `Tuist/Package.swift`.

## 근거
"반복되는 것은 모듈로" 원칙을 도구가 강제한다(의존 그래프 위반은 생성 실패). pbxproj를 커밋하지 않아 혼자여도 충돌이 없다.

## 결과
쉬워짐: 모듈 추가·의존 검사·캐시 빌드. 어려워짐: `tuist generate`를 잊으면 Xcode가 옛 그래프를 본다(Makefile로 감춤).

## 되돌리는 조건
Tuist가 필요한 Xcode 기능을 막을 때(현재 없음). 그때는 SPM 단일 패키지로 되돌리며 모듈 경계는 유지한다.
