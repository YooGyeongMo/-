"""서버 사전(`services/api/app/decode/infra/seed_terms.py`)에 맞춘 학습용 용어표 (ADR-0023).

실험 사전(`terms.py`, 145개)과 서버 사전(132개 + 이형 표기)은 다르다. 서버에 실을 모델은 **서버가
판교어라고 부르는 것**을 배워야 한다:

- 양성(학습 정답) = 서버 용어의 표준 표기 + 이형 표기 + 짧은 영어 원어. 품사(n/v/a)와 '새 표기'
  (평가 전용, 학습·사전 둘 다 제외)는 표기가 겹치는 `terms.py` 항목에서 가져온다.
- 서버가 일부러 뺀 말(seed_terms 머리말: 한 글자·평범한 한국어·팀 안 은어) = **학습 하드 네거티브**.
  예: 회고·배포·지표·우선순위·스프린트·이슈·미팅. 실험 모델은 이것들을 판교어로 배웠다.
- 신규 용어(평가 전용) = `terms.py`에만 있고 서버에 없는 외래 업무어 10개. 학습에도 사전에도 없다.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from terms import TERMS as EXP_TERMS  # noqa: E402

# 서버 정책상 판교어가 아닌 말(사전에 일부러 넣지 않음) → 학습에서 '평범한 말'로 쓴다.
SERVER_ORDINARY_NOUNS = [
    "이슈",
    "프로세스",
    "스프린트",
    "워크샵",
    "시안",
    "요구사항",
    "투명성",
    "지표",
    "우선순위",
    "전환율",
    "병목",
    "가시성",
    "기획서",
    "결과물",
    "초안",
]
SERVER_ORDINARY_VERBS = ["회고", "배포", "자동화", "미팅", "오픈", "픽스"]

# 서버 사전에 없는 외래 업무어 → '신규 용어' 평가 전용(학습 X, 사전 X).
NEW_TERMS = [
    "프레젠테이션",
    "디버깅",
    "오프보딩",
    "리프레시",
    "레벨업",
    "클로징",
    "이그제큐션",
    "어카운터빌리티",
    "탑다운피드백",
    "레드팀",
]

# terms.py 와 표기가 겹치지 않는 서버 용어의 품사(하다가 붙으면 v).
_POS_SERVER_ONLY = {
    "scope-out": "v",
    "next": "n",
    "challenge": "n",
    "fyi": "n",
    "eod": "n",
    "touch-base": "v",
    "pending": "n",
    "issue-up": "v",
    "wrap-up": "v",
    "breakdown": "v",
    "work-load": "n",
    "push": "v",
}


def _short_en(en: str | None) -> bool:
    return bool(en) and len(en) <= 15 and len(en.split()) <= 2


def server_table(seed_terms):
    """반환 (known, new, ordinary_n, ordinary_v). known/new 원소 = (표준, 품사, [이형], [새 표기])."""
    surf_of_slug: dict[str, list[str]] = {}
    slug_of_surface: dict[str, str] = {}
    for t in seed_terms:
        ss = [t.ko, *t.aliases] + ([t.en] if _short_en(t.en) else [])
        uniq = list(dict.fromkeys(s for s in ss if s))
        surf_of_slug[t.slug] = uniq
        for s in (t.ko, t.en, *t.aliases):
            if s:
                slug_of_surface.setdefault(s.lower(), t.slug)
    pos_of: dict[str, str] = {}
    novel_of: dict[str, list[str]] = {}
    for canon, pos, var, novel in EXP_TERMS:
        hits = {slug_of_surface[s.lower()] for s in [canon, *var] if s.lower() in slug_of_surface}
        if canon in SERVER_ORDINARY_NOUNS + SERVER_ORDINARY_VERBS:
            continue
        for slug in hits:
            pos_of.setdefault(slug, pos)
            for nv in novel:
                if nv.lower() not in slug_of_surface:
                    novel_of.setdefault(slug, []).append(nv)
    known = []
    for t in seed_terms:
        surfaces = surf_of_slug[t.slug]
        pos = pos_of.get(t.slug) or _POS_SERVER_ONLY.get(t.slug, "n")
        known.append((surfaces[0], pos, surfaces[1:], novel_of.get(t.slug, [])))
    new = []
    for canon, pos, var, _novel in EXP_TERMS:
        if canon in NEW_TERMS:
            vs = [v for v in var if v.lower() not in slug_of_surface and v != canon]
            new.append((canon, pos, vs, []))
    assert len(new) == len(NEW_TERMS), "NEW_TERMS 가 terms.py 에 다 있어야 한다"
    return known, new, SERVER_ORDINARY_NOUNS, SERVER_ORDINARY_VERBS

# ---------- 2차(ADR-0023 §근거): 평범한 말 어휘 확대 ----------
# 1차 학습의 오탐(마우스·스마트폰·"번거로우시겠지")을 본 뒤 새로 쓴 목록이다. 기존 어휘(terms.py
# NEG_*·gen.py PLAIN_*)·테스트 템플릿 낱말(티켓·슬랙·주차·출장…)·서버 사전 표기와 겹치지 않는다.
# 짝수 = 학습, 홀수 = 새 평가셋 test_fresh_neg 전용(학습에 없음). 이 목록 자체가 1차 실패를 보고
# 만든 것이라 2차 숫자는 그만큼 낙관적일 수 있다(ADR-0023 에 적음).
EXTRA_ORDINARY = """인터넷 와이파이 블루투스 유튜브 넷플릭스 블로그 쇼핑 호텔 레스토랑 메뉴 샐러드 피자
햄버거 샌드위치 케이크 아이스크림 주스 라떼 아메리카노 티셔츠 바지 스웨터 코트 가방 지갑 우산
텔레비전 라디오 냉장고 세탁기 전자레인지 헤드폰 이어폰 충전기 배터리 케이블 스피커 리모컨 와인
맥주 사이다 버터 치즈 소스 오븐 프라이팬 테이블 소파 침대 커튼 카펫 에스컬레이터 아파트 빌딩
오피스텔 마트 편의점 백화점 헬스장 요가 골프 테니스 야구 수영 볼링 캠핑 드라이브 콘서트
뮤지컬 영화 드라마 게임 앨범 노래방 피아노 바이올린 쿠폰 마일리지 카드 계좌 여권 리조트 비행기
공항 기차 자전거 오토바이 주유소 신호등 병원 약국 감기 마스크 비타민 홍차 녹차 도시락 김밥
라면 떡볶이 비빔밥 치킨 생선 과일 바나나 포도 딸기 수박 우유 장마 태풍 미세먼지 공원 도서관
학교 학원 숙제 시험 방학 졸업 동창 친구 가족 부모님 강아지 고양이 화분 꽃다발 선풍기 난로
관리비 월세 이사 청소 빨래 설거지 장보기 요리 운동 산책 낮잠 샴푸 치약 휴지 볼펜 노트 달력
스티커 테이프 가위 풀 클립 파일철 화이트보드 마커 포스트잇 쓰레기통""".split()
EXTRA_TRAIN = EXTRA_ORDINARY[0::2]
EXTRA_FRESH = EXTRA_ORDINARY[1::2]

# 여는 말(문장 앞 평범한 구). 학습용과 새 평가셋용을 손으로 나눴다. '-시겠지만' 꼴은 1차 오탐을 본
# 뒤라 학습에 넣지 않고 평가 쪽에만 둔다(보고 고치는 효과를 빼려고).
FILLERS_TRAIN = ["죄송하지만", "괜찮으시면", "말씀드렸듯이", "혹시 시간 되시면", "아까 말씀드린",
                 "편하실 때", "늦었지만", "다름이 아니라", "부담 없이", "생각해 보니", "제가 알기로",
                 "점심 먹고", "회의 끝나고", "천천히", "아무래도", "어쨌든", "사실은", "다행히"]
FILLERS_FRESH = ["바쁘시겠지만", "힘드시겠지만", "가능하시면", "실례지만", "듣기로는", "어제 얘기한",
                 "퇴근길에", "시간 나실 때", "다시 보니", "그나저나", "하여튼", "아마도"]

# 하다가 붙는 것(v 슬롯: "청소해서")
EXTRA_VERBS = [w for w in EXTRA_ORDINARY if w in {"쇼핑", "요가", "수영", "캠핑", "드라이브", "이사",
                                                  "청소", "빨래", "설거지", "요리", "운동", "산책"}]
