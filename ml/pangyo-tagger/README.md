# 판교어 탐지 모델 실험 (ADR-0018, #101)

합성 데이터만 쓴다(실사용자 원문 0, ADR-0008). 데이터·모델·결과(`data/`, `out/`, 약 29MB)는 커밋하지 않고 아래로 다시 만든다.
재현 순서와 결과 표는 [REPORT.md](REPORT.md) §8.

| 파일 | 하는 일 |
|---|---|
| `terms.py` | 실험용 판교어 145개(신규 용어 15개 분리) |
| `gen.py` | 시드 고정 합성 문장·BIO 스팬 생성 |
| `prep.py` | Create ML 입력 형식 변환 |
| `train.swift` | Create ML `MLWordTagger` 학습(CRF / OS 한국어 임베딩) |
| `tok.swift`, `tokcheck.swift` | 토큰화와 유니코드 스칼라 인덱스 일치 검사 |
| `conf.swift`, `timing.swift` | 확률·지연 측정 |
| `score.py` | 스팬 F1·오탐 집계 |
