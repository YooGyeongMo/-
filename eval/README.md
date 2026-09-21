# eval/ — AI 평가·비용 (FD-5·FD-6 / ADR-0007·0009, REQ-10~13)

저장소 루트의 `eval/` 는 라우팅 결정의 근거를 만드는 곳이다. 표준 라이브러리만 쓴다(REQ-23, 자체 YAML 파서 금지 → TOML).

| 파일 | 역할 |
|---|---|
| `run.py` | 4트랙 평가 하네스 뼈대. 데이터셋 로드 · 엔진 어댑터 `Protocol` · 채점기 3종 · 응답 캐시. 어댑터는 스텁(`NotImplementedError`) — 실제 호출 코드는 S2 타임박스 |
| `dataset/README.md` | 200문장 구성과 JSONL 형식(`gold` = `TranslationResponse` 부분집합). `v0_50.jsonl`·`v1_200.jsonl` 은 S2 |
| `cost_model.py` | MAU당 월 원가 산정기 (`make cost MAU=1000`) |
| `pricing.toml` | 단가·무료 한도 **자리표시자**. 전 항목 `unverified = true`, 숫자 없음. 갱신 절차는 파일 머리 |
| `pricing.example.toml` | **가정값, 사실 아님.** 구조 시연·테스트 전용 |
| `usage.toml` | 1인당 월 사용량 가정(`source = "assumption"`) |
| `measured/` | 실측(usage_snapshot.py 출력·점수표 원본). **.gitignore, 비공개** |
| `cache/` | run.py 응답 캐시. .gitignore |
| `scores/` | 점수표 markdown (커밋함) |
| `tests/` | `python3 -m pytest eval/tests -q` |

## cost_model.py

```
python3 eval/cost_model.py --mau 1000 [--scenario oci_free|aws_t4g_small] [--track gemini_free ...] [--format md|json]
                            [--pricing eval/pricing.toml] [--usage eval/usage.toml] [--conversion 0.05] [--margin 0.5]
```

계산(FD-6):
- 월 원가 = Σ트랙(호출 × 토큰 × 단가) + STT 사슬 + 저장(R2, 오디오 30일) + 고정비(시나리오).
- 무료 한도는 **일 RPD 와 피크 RPM 둘 다** 적용(RT-B-08). RPM 은 `피크 RPM = 일 호출/1440 × peak.factor` 로 보고, 초과 시 `free_rpm/피크 RPM` 비율만 무료로 인정(보수적).
- 초과분은 모델의 `over_limit` 대로 `pay`(단가 과금) / `fallback`(다음 모델로) / `degrade`(503, 거절 건수 경고).
- STT 사슬 `[[stt.chain]]` 은 순서대로 오디오 분을 흡수. `selfhost = true`(whisper_local) 단계는 시나리오 CPU 예산(`vcpus × 43,200분 × cpu_utilization_cap`)까지만 받고, 비용은 VM 시간 배분액으로 따로 보여 주되 **합계에 더하지 않는다**(고정비에 이미 포함). 외부 단계는 `free_sec_per_day` 초과분 × `usd_per_minute`.
- 온디바이스 비율(`ondevice_rate`)은 호출 수에서 **한 번만** 뺀다(RT-B-14). v1.0 = 0.
- 출력: 트랙 비교표, 손익분기 표시가(`total/(1-margin)/(MAU×conversion)/(1-store_fee)×(1+vat)`), 무료 한도 소진 MAU(RPD·RPM 각각, 어느 쪽이 먼저 묶이는지), 경고, 미확인 항목 목록.

### 단가 규칙
- 값이 미확인이면 **키를 생략**하고 `unverified = true` (tomllib 에 null 없음). 산정기는 0 으로 계산하고 "단가 미확인" 경고를 붙인다.
- 확인하면 값 + `verified_on = "YYYY-MM-DD"` + `source = "<URL>"` + `unverified = false`. PR 본문에 `make cost MAU=1000` 결과 첨부. ADR 불필요.
- `tests/test_cost_model.py::test_pricing_toml_has_no_unverified_numbers` 가 `pricing.toml` 에 확인되지 않은 숫자가 들어가는 것을 막는다.

## run.py

```
python3 eval/run.py --engine none --limit 10 [--dataset eval/dataset/v0_50.jsonl] [--sample 40 --seed 20260921] [--cache-dir eval/cache]
```
CI(PR)에서는 외부 호출 0(FD-4): 캐시 적중분만 채점. 야간 40문장 회전, 릴리스 200문장(QA-2).

## 테스트
```
uv run --python 3.14 --with pytest python -m pytest eval/tests -q     # 또는 python3 -m pytest eval/tests -q (pytest 설치 시)
```
