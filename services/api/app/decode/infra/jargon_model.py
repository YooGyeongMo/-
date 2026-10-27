"""문맥 판교어 탐지기 추론(글자 CRF, python-crfsuite, ADR-0023).

- 모델 파일은 이 패키지 안(`model/jargon_crf.crfsuite`)에 있고 같은 이름의 `.json` 메타데이터가
  특징 버전·임계값·sha256 을 적는다. 파일이 없거나 버전·해시가 맞지 않으면 **모델 없이** 돈다
  (사전만 = ADR-0023 이전과 같은 결과). 그 사실만 경고로 남기고 원문은 어디에도 싣지 않는다.
- 처음 쓸 때 한 번만 읽는다(지연 로드, 잠금으로 한 번). crfsuite Tagger 는 set → tag → marginal
  사이에 상태를 쥐므로 호출 전체를 잠금 안에서 한다. 문장 하나 1ms 미만이라 잠금 대기는 짧다.
- 원문은 서버 밖으로 나가지 않는다(ADR-0008, REQ-14): 이 모듈은 네트워크를 쓰지 않는다.
"""

import hashlib
import json
import logging
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from app.decode.domain.jargon_features import (
    FEATURE_VERSION,
    Candidate,
    decode,
    features,
    positions,
)

log = logging.getLogger(__name__)

MODEL_DIR = Path(__file__).resolve().parent / "model"
MODEL_PATH = MODEL_DIR / "jargon_crf.crfsuite"
META_PATH = MODEL_DIR / "jargon_crf.json"
DEFAULT_THRESHOLD = 0.9


def has_hangul(text: str) -> bool:
    return any("가" <= ch <= "힣" for ch in text)


@dataclass(frozen=True)
class ModelInfo:
    feature_version: str
    threshold: float
    sha256: str


class CrfJargonTagger:
    """모델 파일 하나를 감싼다. `candidates`는 스레드 안전."""

    def __init__(self, model_path: Path) -> None:
        import pycrfsuite  # 지연 import: 모델을 끈 프로세스는 C 확장을 읽지 않는다

        self._tagger: Any = pycrfsuite.Tagger()
        self._tagger.open(str(model_path))
        self._lock = threading.Lock()

    def candidates(self, text: str) -> list[Candidate]:
        """원문 → 모델 스팬 후보(관문 전). 한글이 없는 문장은 학습 분포 밖이라 보지 않는다."""
        if not has_hangul(text):
            return []
        pos = positions(text)
        xseq = features(text)
        if not xseq:
            return []
        with self._lock:
            self._tagger.set(xseq)
            labels: list[str] = list(self._tagger.tag())
            probs = [float(self._tagger.marginal(lab, k)) for k, lab in enumerate(labels)]
        return decode(pos, labels, probs)


def read_info(meta_path: Path = META_PATH) -> ModelInfo | None:
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        return ModelInfo(
            str(meta["feature_version"]), float(meta["threshold"]), str(meta["sha256"])
        )
    except (OSError, ValueError, KeyError, TypeError):
        return None


def load(model_path: Path = MODEL_PATH, meta_path: Path = META_PATH) -> CrfJargonTagger | None:
    """모델을 읽는다. 쓸 수 없으면 None(사전만으로 돈다)."""
    info = read_info(meta_path)
    if info is None or not model_path.is_file():
        log.warning("jargon_model_unavailable reason=missing")
        return None
    if info.feature_version != FEATURE_VERSION:
        log.warning("jargon_model_unavailable reason=feature_version")
        return None
    if hashlib.sha256(model_path.read_bytes()).hexdigest() != info.sha256:
        log.warning("jargon_model_unavailable reason=sha256")
        return None
    try:
        return CrfJargonTagger(model_path)
    except Exception:  # C 확장이 파일을 못 읽음 → 모델 없이(사전만) 돈다
        log.warning("jargon_model_unavailable reason=open_failed")
        return None


_lock = threading.Lock()
_loaded = False
_tagger: CrfJargonTagger | None = None


def shared() -> CrfJargonTagger | None:
    """프로세스에 하나. 처음 부를 때 읽고, 실패도 기억한다(요청마다 다시 읽지 않는다)."""
    global _loaded, _tagger
    if _loaded:
        return _tagger
    with _lock:
        if not _loaded:
            _tagger = load()
            _loaded = True
    return _tagger


def reset() -> None:
    """테스트용: 다음 `shared()`가 다시 읽게 한다."""
    global _loaded, _tagger
    with _lock:
        _loaded = False
        _tagger = None
