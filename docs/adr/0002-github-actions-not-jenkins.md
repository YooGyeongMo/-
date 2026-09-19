# ADR-0002: CI/CD는 GitHub Actions(+ self-hosted macOS 러너)로, Jenkins는 쓰지 않는다

- 상태: 채택 (2026-09-19)
- 관련: 설계 13번 §5, 이슈 #1

## 맥락
앱(iOS·macOS) 빌드는 macOS가 필요하고, 서버는 리눅스 컨테이너다. 혼자 운영한다.

## 선택지
| 선택지 | 장점 | 단점 |
|---|---|---|
| Jenkins(자체 서버) | 파이프라인 자유, 기업 채용 공고에 자주 등장 | 서버 한 대를 더 운영·보안·플러그인 관리, macOS 노드는 결국 내 Mac |
| GitHub Actions hosted | 저장소와 한 몸, 서버 job 무료 한도 | macOS 러너는 분당 요금 높고 느림 |
| GitHub Actions + self-hosted macOS 러너(내 Mac) | 앱 빌드가 빠르고 무료, Tuist 캐시 재사용 | 내 Mac이 꺼지면 앱 CI 대기 → hosted 폴백 |
| Xcode Cloud | 애플 통합 | Tuist·모노레포와 궁합, 서버 job 불가 |

## 결정
GitHub Actions. 서버 job은 hosted ubuntu, 앱 job은 self-hosted macOS 러너(라벨 `self-hosted, macOS`)를 우선하고 `macos-15`를 폴백으로.

## 근거
운영할 것을 늘리지 않는다. Jenkins 경험은 "왜 안 썼는가"를 설명할 수 있으면 충분하다.

## 결과
쉬워짐: PR 하나에 앱·서버·계약 검사가 같이 돈다. 어려워짐: self-hosted 러너 등록·보안(공개 저장소에서는 fork PR에 self-hosted를 쓰지 않도록 `pull_request_target` 금지).

## 되돌리는 조건
팀이 생겨 조직 표준이 Jenkins일 때.
