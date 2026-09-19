# ADR-0004: 저장소는 모노레포 하나, 번들 ID 접두는 `kr.mwonmal`

- 상태: 제안 (2026-09-19) — 저장소 이름 `-`는 `mwonmal`로 바꾸는 것을 권고
- 관련: 설계 13번 E-1, 14번 §16

## 맥락
사용자가 `YooGyeongMo/-`(공개)를 만들어 클론했다. 이름이 `-`이면 경로·CLI(`cd -`, `git -C -`)와 충돌한다.

## 선택지
| 선택지 | 장점 | 단점 |
|---|---|---|
| `-` 유지 | 지금 그대로 | 도구 충돌, 검색 불가, 포트폴리오에서 이름이 안 보임 |
| `mwonmal`로 rename | GitHub가 옛 URL을 리다이렉트, 클론 폴더만 바꾸면 됨 | 한 번의 rename |

## 결정
`gh repo rename mwonmal` 권고(사용자 확인 후). 번들 ID `kr.mwonmal.app`(iOS), `kr.mwonmal.mac`(macOS), 앱 그룹 `group.kr.mwonmal`. 공개 저장소이므로 시크릿·개인정보는 절대 커밋하지 않는다(gitleaks 게이트).

## 되돌리는 조건
없음.
