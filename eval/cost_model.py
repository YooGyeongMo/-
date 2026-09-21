"""REQ-13 / FD-6 / ADR-0009 — MAU당 월 원가 산정기. 표준 라이브러리만(tomllib·dataclasses·argparse).

입력
  pricing.toml  단가·무료 한도. 값이 미확인이면 키를 생략하고 unverified = true (null 금지).
  usage.toml    1인당 월 사용량 가정(source = "assumption"). 실측은 eval/measured/usage.toml(비공개).
계산 (FD-6)
  월 원가 = Σ트랙(호출 × 토큰 × 단가, 무료 한도는 일 RPD와 피크 RPM 둘 다 적용해 초과분만)
          + STT 사슬([[stt.chain]] 순서대로 흡수: 무료 초/일 → 분당 단가 → 자체 서빙 CPU 분)
          + 저장(R2, 오디오 retention_days) + 고정비(시나리오 oci_free = 0 기본, aws_t4g_small 옵션)
  온디바이스 비율은 호출 수 계산에서 한 번만 적용한다(RT-B-14).
출력  월 원가, MAU당 원가, 손익분기 구독가(마진·전환율), 무료 한도 소진 MAU, 트랙 비교 markdown 표 / json.
사용  python3 eval/cost_model.py --mau 1000 [--scenario oci_free] [--format md|json]   (= make cost MAU=1000)
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import tomllib
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

DAYS_PER_MONTH = 30
MINUTES_PER_DAY = 24 * 60
MB_PER_GB = 1024
HERE = Path(__file__).resolve().parent


# ---------------------------------------------------------------------------
# 1. 입력 스키마 — 가격 키는 전부 Optional. None = "미확인(키 생략)" → 청구 시 unpriced 경고
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ModelPrice:
    model_id: str
    provider: str = ""
    input_per_mtok: float | None = None
    cached_input_per_mtok: float | None = None
    output_per_mtok: float | None = None
    free_rpd: int | None = None
    free_rpm: int | None = None
    over_limit: str = "pay"  # pay | fallback | degrade
    fallback_model: str | None = None
    unverified: bool = True
    verified_on: str = ""
    source: str = ""

    @property
    def priced(self) -> bool:
        return self.input_per_mtok is not None and self.output_per_mtok is not None


@dataclass(frozen=True)
class SttStage:
    """STT 사슬의 한 단계. 순서대로 오디오 분을 흡수한다."""

    name: str
    free_sec_per_day: float = 0.0
    usd_per_minute: float | None = None
    selfhost: bool = False  # 자체 서빙(whisper_local, faster-whisper CPU). 비용 = CPU 분 × VM 시간 배분(고정비에 이미 포함 → 합계엔 미가산)
    selfhost_cpu_min_per_audio_min: float | None = None  # 오디오 1분당 CPU 분(실측). 미확인이면 용량·배분 계산 불가 → 경고
    max_share: float = 1.0  # 이 단계가 받을 수 있는 최대 비율(0~1)
    unverified: bool = True
    verified_on: str = ""
    source: str = ""


@dataclass(frozen=True)
class StoragePrice:
    provider: str = ""
    usd_per_gb_month: float | None = None
    free_gb: float = 0.0
    usd_per_million_class_a: float | None = None
    free_class_a_per_month: float = 0.0
    unverified: bool = True
    verified_on: str = ""
    source: str = ""


@dataclass(frozen=True)
class FixedScenario:
    name: str
    usd_per_month: float | None = None
    vcpus: float = 0.0
    cpu_utilization_cap: float = 0.7
    label: str = ""
    unverified: bool = True
    verified_on: str = ""
    source: str = ""

    @property
    def cpu_minutes_per_month(self) -> float:
        return self.vcpus * DAYS_PER_MONTH * MINUTES_PER_DAY * self.cpu_utilization_cap

    @property
    def usd_per_cpu_minute(self) -> float:
        cap = self.vcpus * DAYS_PER_MONTH * MINUTES_PER_DAY
        return (self.usd_per_month or 0.0) / cap if cap else 0.0


@dataclass(frozen=True)
class TaskTokens:
    input_tokens: int = 0
    cached_tokens: int = 0
    output_tokens: int = 0
    per_minute_input_tokens: int = 0  # 회의 받아쓰기처럼 길이 비례 입력


@dataclass(frozen=True)
class Track:
    """작업 → 모델 배정. FD-4: 요청 1회에 4필드 전부 생성 → 작업 = translate / meeting / summary."""

    name: str
    translate: str | None = None
    meeting: str | None = None
    summary: str | None = None
    note: str = ""


@dataclass(frozen=True)
class Pricing:
    fx_krw_per_usd: float
    models: dict[str, ModelPrice]
    stt_chain: tuple[SttStage, ...]
    storage: StoragePrice
    scenarios: dict[str, FixedScenario]
    tasks: dict[str, TaskTokens]
    tracks: dict[str, Track]
    audio_mb_per_minute: float = 1.0
    audio_retention_days: int = 30
    unverified: tuple[str, ...] = ()  # 미확인 항목 이름 목록


@dataclass(frozen=True)
class UsageProfile:
    """1인당 월 사용량(전부 가정 → 실측 갱신)."""

    translations: float = 0.0
    meeting_decodes: float = 0.0
    recording_minutes: float = 0.0
    reviews: float = 0.0
    dictionary_only_rate: float = 0.0
    cache_hit_rate: float = 0.0
    ondevice_rate: float = 0.0  # v1.0 = 0 (온디바이스는 미리보기만, 정본은 서버 — FD-5)
    long_meeting_rate: float = 0.0
    peak_factor: float = 5.0  # 피크 RPM / 평균 RPM (퇴근길 몰림)
    source: str = "assumption"


# ---------------------------------------------------------------------------
# 2. 로더
# ---------------------------------------------------------------------------


def _pick(d: dict[str, Any], cls: type) -> dict[str, Any]:
    names = cls.__dataclass_fields__  # type: ignore[attr-defined]
    return {k: v for k, v in d.items() if k in names}


def load_pricing(path: Path) -> Pricing:
    with path.open("rb") as f:
        d = tomllib.load(f)
    unverified: list[str] = []
    fx = d.get("fx", {})
    if fx.get("unverified", True):
        unverified.append("fx.krw_per_usd")
    models = {k: ModelPrice(model_id=k, **_pick(v, ModelPrice)) for k, v in d.get("models", {}).items()}
    unverified += [f"models.{m.model_id}" for m in models.values() if m.unverified]
    chain = tuple(SttStage(**_pick(s, SttStage)) for s in d.get("stt", {}).get("chain", []))
    unverified += [f"stt.{s.name}" for s in chain if s.unverified]
    storage = StoragePrice(**_pick(d.get("storage", {}), StoragePrice))
    if storage.unverified:
        unverified.append("storage")
    scenarios = {k: FixedScenario(name=k, **_pick(v, FixedScenario)) for k, v in d.get("fixed", {}).items()}
    unverified += [f"fixed.{s.name}" for s in scenarios.values() if s.unverified]
    tasks = {k: TaskTokens(**_pick(v, TaskTokens)) for k, v in d.get("tasks", {}).items()}
    tracks = {k: Track(name=k, **_pick(v, Track)) for k, v in d.get("tracks", {}).items()}
    audio = d.get("audio", {})
    return Pricing(
        fx_krw_per_usd=float(fx.get("krw_per_usd", 0.0)),
        models=models,
        stt_chain=chain,
        storage=storage,
        scenarios=scenarios,
        tasks=tasks,
        tracks=tracks,
        audio_mb_per_minute=float(audio.get("mb_per_minute", 1.0)),
        audio_retention_days=int(audio.get("retention_days", 30)),
        unverified=tuple(unverified),
    )


def load_usage(path: Path) -> UsageProfile:
    with path.open("rb") as f:
        d = tomllib.load(f)
    per_user = d.get("per_user_month", {})
    return UsageProfile(
        **_pick(per_user, UsageProfile),
        peak_factor=float(d.get("peak", {}).get("factor", 5.0)),
        source=str(d.get("source", "assumption")),
    )


# ---------------------------------------------------------------------------
# 3. 호출량
# ---------------------------------------------------------------------------


@dataclass
class CallVolume:
    task: str
    model_id: str | None
    calls: float
    input_tokens: float
    cached_tokens: float
    output_tokens: float


def calls_per_user(u: UsageProfile) -> dict[str, float]:
    """1인당 월 서버 AI 호출 수. 사전-only·10분 캐시·온디바이스 비율은 여기서 **한 번만** 뺀다(RT-B-14)."""
    ai_translations = u.translations * (1 - u.dictionary_only_rate) * (1 - u.cache_hit_rate) * (1 - u.ondevice_rate)
    return {
        "translate": ai_translations,
        "meeting": u.meeting_decodes,
        "summary": u.meeting_decodes * u.long_meeting_rate,
    }


def volumes(mau: int, u: UsageProfile, p: Pricing, track: Track) -> list[CallVolume]:
    assignment = {"translate": track.translate, "meeting": track.meeting, "summary": track.summary}
    out: list[CallVolume] = []
    for task, per_user in calls_per_user(u).items():
        calls = per_user * mau
        t = p.tasks.get(task, TaskTokens())
        extra_in = 0.0
        if t.per_minute_input_tokens and u.meeting_decodes:
            extra_in = (u.recording_minutes / u.meeting_decodes) * t.per_minute_input_tokens
        out.append(
            CallVolume(
                task=task,
                model_id=assignment[task],
                calls=calls,
                input_tokens=calls * (t.input_tokens + extra_in),
                cached_tokens=calls * t.cached_tokens,
                output_tokens=calls * t.output_tokens,
            )
        )
    return out


# ---------------------------------------------------------------------------
# 4. 모델 청구 — 무료 한도: RPD와 피크 RPM 둘 다(RT-B-08)
# ---------------------------------------------------------------------------


def free_calls_per_day(m: ModelPrice, calls_per_day: float, peak_factor: float) -> tuple[float, str]:
    """무료로 처리 가능한 일 호출 수와 어느 한도가 묶었는지('rpd'|'rpm'|'none'|'no_free').
    RPM은 피크 시간대 초과분이 거절된다고 보고, 하루 전체에 (free_rpm / peak_rpm) 비율을 보수적으로 적용."""
    if m.free_rpd is None and m.free_rpm is None:
        return 0.0, "no_free"
    by_rpd = float(m.free_rpd) if m.free_rpd is not None else math.inf
    by_rpm = math.inf
    if m.free_rpm is not None:
        peak_rpm = calls_per_day / MINUTES_PER_DAY * peak_factor
        if peak_rpm > m.free_rpm:
            by_rpm = calls_per_day * (m.free_rpm / peak_rpm)
    free = min(calls_per_day, by_rpd, by_rpm)
    if free >= calls_per_day:
        return free, "none"
    return free, ("rpm" if by_rpm < by_rpd else "rpd")


@dataclass
class ModelBill:
    model_id: str
    calls: float
    free_calls: float
    billable_calls: float
    usd: float
    binding_limit: str
    peak_rpm_needed: float
    over_limit_action: str
    unpriced: bool
    dropped_calls: float = 0.0  # degrade → 503


def bill_models(vols: list[CallVolume], p: Pricing, peak_factor: float) -> list[ModelBill]:
    pending: dict[str, list[CallVolume]] = {}
    for v in vols:
        if v.model_id is not None and v.calls > 0:
            pending.setdefault(v.model_id, []).append(v)
    bills: dict[str, ModelBill] = {}
    for _hop in range(4):  # 폴백 최대 3단
        if not pending:
            break
        next_pending: dict[str, list[CallVolume]] = {}
        for mid, vs in pending.items():
            m = p.models[mid]
            calls = sum(v.calls for v in vs)
            prev = bills.get(mid)
            already = prev.calls if prev else 0.0
            total_day = (already + calls) / DAYS_PER_MONTH
            free_day, binding = free_calls_per_day(m, total_day, peak_factor)
            free_month_left = max(0.0, free_day * DAYS_PER_MONTH - (prev.free_calls if prev else 0.0))
            free_calls = min(calls, free_month_left)
            billable = calls - free_calls
            share = billable / calls if calls else 0.0
            in_tok = sum(v.input_tokens for v in vs) * share
            cached = sum(v.cached_tokens for v in vs) * share
            out_tok = sum(v.output_tokens for v in vs) * share
            usd, dropped, unpriced = 0.0, 0.0, False
            if billable > 0:
                if m.over_limit == "pay":
                    if m.priced:
                        cached_price = m.cached_input_per_mtok if m.cached_input_per_mtok is not None else m.input_per_mtok
                        usd = (
                            in_tok * float(m.input_per_mtok or 0)
                            + cached * float(cached_price or 0)
                            + out_tok * float(m.output_per_mtok or 0)
                        ) / 1e6
                    else:
                        unpriced = True
                elif m.over_limit == "fallback" and m.fallback_model:
                    next_pending.setdefault(m.fallback_model, []).append(
                        CallVolume(f"overflow<-{mid}", m.fallback_model, billable, in_tok, cached, out_tok)
                    )
                else:  # degrade
                    dropped = billable
            bills[mid] = ModelBill(
                model_id=mid,
                calls=already + calls,
                free_calls=(prev.free_calls if prev else 0.0) + free_calls,
                billable_calls=(prev.billable_calls if prev else 0.0) + billable,
                usd=(prev.usd if prev else 0.0) + usd,
                binding_limit=binding,
                peak_rpm_needed=total_day / MINUTES_PER_DAY * peak_factor,
                over_limit_action=m.over_limit,
                unpriced=(prev.unpriced if prev else False) or unpriced,
                dropped_calls=(prev.dropped_calls if prev else 0.0) + dropped,
            )
        pending = next_pending
    return list(bills.values())


# ---------------------------------------------------------------------------
# 5. STT 사슬 · 저장 · 고정비
# ---------------------------------------------------------------------------


@dataclass
class SttBill:
    stage: str
    minutes: float
    free_minutes: float
    usd: float  # 외부 단계: 실제 청구. 자체 서빙: VM 시간 배분액(고정비에 포함, 합계엔 미가산)
    selfhost: bool = False
    cpu_minutes: float = 0.0
    unpriced: bool = False


def bill_stt(audio_minutes: float, p: Pricing, scenario: FixedScenario) -> tuple[list[SttBill], float]:
    """사슬 순서대로 흡수. 자체 서빙 단계는 시나리오 CPU 예산(vcpus × 월 분 × 사용률 상한)까지만 받는다.
    반환 (단계별 청구, 사슬 끝까지 못 받은 분 = 거절)."""
    remaining = audio_minutes
    out: list[SttBill] = []
    for s in p.stt_chain:
        if remaining <= 0:
            break
        capacity = audio_minutes * s.max_share
        cpu_per_audio = s.selfhost_cpu_min_per_audio_min
        if s.selfhost and cpu_per_audio:
            capacity = min(capacity, scenario.cpu_minutes_per_month / cpu_per_audio)
        taken = min(remaining, capacity)
        free_min = min(taken, s.free_sec_per_day * DAYS_PER_MONTH / 60)
        billable = taken - free_min
        usd, cpu_min, unpriced = 0.0, 0.0, False
        if s.selfhost:
            if cpu_per_audio is None:
                unpriced = True  # CPU 분/오디오 분 미실측 → 용량 무한·배분 0 으로 계산됨
            else:
                cpu_min = taken * cpu_per_audio
                usd = cpu_min * scenario.usd_per_cpu_minute
        elif billable > 0:
            if s.usd_per_minute is None:
                unpriced = True
            else:
                usd = billable * s.usd_per_minute
        out.append(SttBill(s.name, taken, free_min, usd, s.selfhost, cpu_min, unpriced))
        remaining -= taken
    return out, max(0.0, remaining)


def storage_usd(mau: int, u: UsageProfile, p: Pricing) -> tuple[float, bool]:
    minutes = mau * u.recording_minutes
    gb = minutes * p.audio_mb_per_minute / MB_PER_GB * (p.audio_retention_days / DAYS_PER_MONTH)
    over_gb = max(0.0, gb - p.storage.free_gb)
    over_ops = max(0.0, minutes - p.storage.free_class_a_per_month)  # 60초 조각 1개 = 쓰기 1회
    unpriced = (over_gb > 0 and p.storage.usd_per_gb_month is None) or (
        over_ops > 0 and p.storage.usd_per_million_class_a is None
    )
    usd = over_gb * float(p.storage.usd_per_gb_month or 0) + over_ops / 1e6 * float(p.storage.usd_per_million_class_a or 0)
    return usd, unpriced


# ---------------------------------------------------------------------------
# 6. 리포트
# ---------------------------------------------------------------------------


@dataclass
class CostReport:
    track: str
    scenario: str
    mau: int
    ai_usd: float
    stt_usd: float  # 외부 STT 청구액만
    stt_selfhost_allocated_usd: float  # whisper_local 에 배분된 VM 시간(고정비 내수, 참고용)
    storage_usd: float
    fixed_usd: float
    total_usd: float
    total_krw: float
    per_mau_krw: float
    variable_per_mau_krw: float
    model_bills: list[ModelBill] = field(default_factory=list)
    stt_bills: list[SttBill] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def estimate(mau: int, u: UsageProfile, p: Pricing, track_name: str, scenario_name: str) -> CostReport:
    track = p.tracks[track_name]
    scenario = p.scenarios[scenario_name]
    bills = bill_models(volumes(mau, u, p, track), p, u.peak_factor)
    ai = sum(b.usd for b in bills)
    stt_bills, dropped_min = bill_stt(mau * u.recording_minutes, p, scenario)
    stt = sum(b.usd for b in stt_bills if not b.selfhost)
    stt_selfhost = sum(b.usd for b in stt_bills if b.selfhost)
    sto, sto_unpriced = storage_usd(mau, u, p)
    fixed = scenario.usd_per_month
    warnings: list[str] = []
    if fixed is None:
        warnings.append(f"fixed.{scenario_name}: 월 고정비 미확인 → 0으로 계산")
        fixed = 0.0
    for b in bills:
        if b.unpriced:
            warnings.append(f"{b.model_id}: 단가 미확인 상태에서 무료 한도 초과 {b.billable_calls:,.0f}건/월 → 과소 계산")
        if b.binding_limit in ("rpd", "rpm"):
            warnings.append(
                f"{b.model_id}: 무료 {b.binding_limit.upper()} 한도 초과 → {b.over_limit_action}"
                f" (초과 {b.billable_calls:,.0f}건/월, 피크 RPM {b.peak_rpm_needed:.1f})"
            )
        if b.dropped_calls:
            warnings.append(f"{b.model_id}: 503 거절 {b.dropped_calls:,.0f}건/월 (degrade)")
    for s in stt_bills:
        if s.unpriced and s.selfhost:
            warnings.append(f"stt.{s.stage}: 오디오 1분당 CPU 분 미실측 → 용량 한도·VM 배분 계산 불가 ({s.minutes:,.0f}분/월)")
        elif s.unpriced:
            warnings.append(f"stt.{s.stage}: 분당 단가 미확인 상태에서 무료 초과 {s.minutes - s.free_minutes:,.0f}분/월")
    if dropped_min > 0:
        warnings.append(f"stt: 사슬 용량 초과 {dropped_min:,.0f}분/월 (CPU 예산 {scenario.cpu_minutes_per_month:,.0f}분) → 거절")
    if sto_unpriced:
        warnings.append("storage: 단가 미확인 상태에서 무료 한도 초과")
    if not p.fx_krw_per_usd:
        warnings.append("fx.krw_per_usd 미확인 → 원화 = 0")
    total = ai + stt + sto + fixed
    krw = total * p.fx_krw_per_usd
    return CostReport(
        track=track_name,
        scenario=scenario_name,
        mau=mau,
        ai_usd=ai,
        stt_usd=stt,
        stt_selfhost_allocated_usd=stt_selfhost,
        storage_usd=sto,
        fixed_usd=fixed,
        total_usd=total,
        total_krw=krw,
        per_mau_krw=krw / mau if mau else 0.0,
        variable_per_mau_krw=(total - fixed) * p.fx_krw_per_usd / mau if mau else 0.0,
        model_bills=bills,
        stt_bills=stt_bills,
        warnings=warnings,
    )


def breakeven_price_krw(
    report: CostReport, conversion: float, margin: float, store_fee: float = 0.15, vat: float = 0.10
) -> dict[str, float]:
    """월 원가를 결제자가 나눠 낼 때의 표시가.
    list = total_krw / (1 - margin) / (MAU × conversion) / (1 - store_fee) × (1 + vat)"""
    payers = max(report.mau * conversion, 1e-9)
    to_list = lambda net: net / payers / (1 - store_fee) * (1 + vat)  # noqa: E731
    return {
        "payers": payers,
        "list_price_breakeven": to_list(report.total_krw),
        "list_price_target_margin": to_list(report.total_krw / (1 - margin)),
    }


def free_limit_mau(model_id: str, u: UsageProfile, p: Pricing) -> dict[str, float | str]:
    """translate 작업이 이 모델의 무료 한도(RPD·RPM)를 소진하는 MAU. 어느 쪽이 먼저 묶이는지도 반환."""
    m = p.models[model_id]
    per_user_day = calls_per_user(u)["translate"] / DAYS_PER_MONTH
    if per_user_day <= 0:
        return {"model": model_id, "mau_rpd": math.inf, "mau_rpm": math.inf, "binding": "none"}
    mau_rpd = m.free_rpd / per_user_day if m.free_rpd is not None else math.inf
    mau_rpm = (
        m.free_rpm / (per_user_day / MINUTES_PER_DAY * u.peak_factor) if m.free_rpm is not None else math.inf
    )
    binding = "none" if mau_rpd == mau_rpm == math.inf else ("rpm" if mau_rpm < mau_rpd else "rpd")
    return {"model": model_id, "mau_rpd": mau_rpd, "mau_rpm": mau_rpm, "binding": binding}


def _fmt_mau(x: float) -> str:
    return "∞" if x == math.inf else f"{x:,.0f}"


def to_markdown(reports: list[CostReport], p: Pricing, u: UsageProfile, conversion: float, margin: float) -> str:
    lines = [
        f"### 원가 비교 (MAU {reports[0].mau:,}, 시나리오 {reports[0].scenario}, usage.source={u.source})",
        "",
        "| 트랙 | AI(USD) | STT 외부(USD) | STT 자체(VM 배분) | 저장(USD) | 고정(USD) | 합계(USD) | 합계(원) | MAU당(원) | 한계원가/MAU(원) | 손익분기 표시가(원) | 경고 |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in reports:
        be = breakeven_price_krw(r, conversion, margin)
        lines.append(
            f"| {r.track} | {r.ai_usd:,.2f} | {r.stt_usd:,.2f} | {r.stt_selfhost_allocated_usd:,.2f} | {r.storage_usd:,.2f} | {r.fixed_usd:,.0f} | "
            f"{r.total_usd:,.2f} | {r.total_krw:,.0f} | {r.per_mau_krw:,.0f} | {r.variable_per_mau_krw:,.0f} | "
            f"{be['list_price_target_margin']:,.0f} | {len(r.warnings)} |"
        )
    lines += ["", f"손익분기 가정: 전환율 {conversion:.0%}, 목표 마진 {margin:.0%}, 스토어 수수료 15%, VAT 10%.", ""]
    free_models = [m for m in p.models.values() if m.free_rpd is not None or m.free_rpm is not None]
    if free_models:
        lines += ["| 무료 한도 소진 MAU | RPD 기준 | RPM 기준(피크) | 먼저 묶이는 것 |", "|---|---|---|---|"]
        for m in free_models:
            f = free_limit_mau(m.model_id, u, p)
            lines.append(f"| {m.model_id} | {_fmt_mau(float(f['mau_rpd']))} | {_fmt_mau(float(f['mau_rpm']))} | {f['binding']} |")
        lines.append("")
    for r in reports:
        for w in r.warnings:
            lines.append(f"- ⚠ [{r.track}] {w}")
    if p.unverified:
        lines += ["", f"> 단가 미확인(unverified=true): {', '.join(p.unverified)} — 사실이 아닌 자리표시자. pricing.toml 갱신 절차는 eval/README.md."]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="REQ-13 / FD-6 MAU당 월 원가 산정기")
    ap.add_argument("--mau", type=int, default=1000)
    ap.add_argument("--scenario", default="oci_free", help="fixed.* 시나리오 (oci_free | aws_t4g_small)")
    ap.add_argument("--pricing", type=Path, default=HERE / "pricing.toml")
    ap.add_argument("--usage", type=Path, default=HERE / "usage.toml")
    ap.add_argument("--track", action="append", help="비우면 전 트랙 비교")
    ap.add_argument("--format", choices=["md", "json"], default="md")
    ap.add_argument("--conversion", type=float, default=0.05, help="유료 전환율(MAU 대비)")
    ap.add_argument("--margin", type=float, default=0.5, help="목표 총마진")
    a = ap.parse_args(argv)
    p = load_pricing(a.pricing)
    u = load_usage(a.usage)
    if a.scenario not in p.scenarios:
        ap.error(f"--scenario {a.scenario}: pricing.toml [fixed.*]에 없음 ({', '.join(p.scenarios)})")
    names = a.track or list(p.tracks)
    reports = [estimate(a.mau, u, p, n, a.scenario) for n in names]
    if a.format == "json":
        payload = {
            "reports": [asdict(r) for r in reports],
            "breakeven": {r.track: breakeven_price_krw(r, a.conversion, a.margin) for r in reports},
            "free_limit_mau": [free_limit_mau(m, u, p) for m in p.models if p.models[m].free_rpd or p.models[m].free_rpm],
            "unverified": list(p.unverified),
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2, default=str))
    else:
        print(to_markdown(reports, p, u, a.conversion, a.margin))
    return 0


if __name__ == "__main__":
    sys.exit(main())
