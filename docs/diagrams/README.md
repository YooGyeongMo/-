# docs/diagrams — archify 그림 (REQ-24)

원본은 `*.json`(archify 스펙), 보이는 것은 `*.png`, 탐색용은 `*.html`(테마·확대·뷰 전환·내보내기 내장).
도구: 로컬 스킬 `~/.claude/skills/archify` (Node 22). 재생성:

```bash
A=~/.claude/skills/archify/bin/archify.mjs
node $A validate <type> <name>.<type>.json --quality showcase --json   # 9개 검사 전부 통과해야 함
node $A deliver  <type> <name>.<type>.json <name>.html --quality showcase --json
node $A visual-check <name>.html --json   # 2048x1320 light PNG를 <name>.png로 보관
```

| 파일 | 타입 | 무엇을 | 근거 |
|---|---|---|---|
| `module-graph` | architecture | Tuist 8모듈 의존 방향, import 금지 경계 | ADR-0001, D-21 |
| `layout-branching` | workflow | 사이즈 클래스 분기 → 루트 2종 → TabCoordinator 상태 보존 | FD-2, ADR-0006 |
| `ai-routing` | workflow | 해석 요청의 사전 우선 → 옵트인·한도 게이트 → 엔진/강등 → 검증·저장, FM 미리보기 | FD-4·5, ADR-0007·0008 |

다음 예정: `push-payload`(sequence, ADR-0010), `cost-flow`(dataflow, ADR-0009), `recording-pipeline`(lifecycle, D-7).
규칙: 그림이 바뀌면 json·html·png 셋을 같은 PR에서 갱신. 야간 CI가 `validate`를 돌린다(ADR-0011).
