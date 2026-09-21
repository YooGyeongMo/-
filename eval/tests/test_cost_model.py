"""eval/cost_model.py 단위·계산 검증. 입력은 pricing.example.toml(가정값)과 인라인 TOML."""

from __future__ import annotations

import json
import math
import sys
import tomllib
from pathlib import Path

import pytest

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))

import cost_model as cm  # noqa: E402

EXAMPLE = EVAL / "pricing.example.toml"
USAGE = EVAL / "usage.toml"


@pytest.fixture
def pricing() -> cm.Pricing:
    return cm.load_pricing(EXAMPLE)


@pytest.fixture
def usage() -> cm.UsageProfile:
    return cm.load_usage(USAGE)


def test_load_example_pricing_collects_unverified(pricing: cm.Pricing) -> None:
    assert pricing.fx_krw_per_usd == 1000
    assert "models.gemini_free" in pricing.unverified
    assert "models.none" not in pricing.unverified  # 설계상 0원은 확인됨
    assert pricing.models["gemini_free"].free_rpd == 200
    assert [s.name for s in pricing.stt_chain] == ["whisper_local", "external_example"]
    assert set(pricing.scenarios) == {"oci_free", "aws_t4g_small"}


def test_pricing_toml_has_no_unverified_numbers() -> None:
    """pricing.toml 규칙: 미확인 항목은 단가 키를 생략한다. 사실처럼 숫자를 넣는 것을 막는다."""
    with (EVAL / "pricing.toml").open("rb") as f:
        d = tomllib.load(f)
    price_keys = {
        "input_per_mtok", "cached_input_per_mtok", "output_per_mtok", "free_rpd", "free_rpm",
        "usd_per_minute", "selfhost_cpu_min_per_audio_min", "usd_per_gb_month", "usd_per_million_class_a", "vcpus",
    }
    sections: list[tuple[str, dict]] = [(f"models.{k}", v) for k, v in d["models"].items()]
    sections += [(f"stt.{s['name']}", s) for s in d["stt"]["chain"]]
    sections += [("storage", d["storage"])] + [(f"fixed.{k}", v) for k, v in d["fixed"].items()]
    for name, sec in sections:
        if sec.get("unverified", True):
            leaked = [k for k in price_keys if k in sec] + (["usd_per_month"] if sec.get("usd_per_month") else [])
            assert not leaked, f"{name}: unverified=true 인데 단가 키가 있음 {leaked}"
            assert sec.get("verified_on") == "" and sec.get("source") == ""
        else:
            assert sec.get("verified_on") and sec.get("source"), f"{name}: 확인됨이면 verified_on·source 필수"
    assert d["fx"].get("unverified") is True and "krw_per_usd" not in d["fx"]


def test_calls_per_user_applies_rates_once() -> None:
    u = cm.UsageProfile(translations=100, meeting_decodes=4, dictionary_only_rate=0.1, cache_hit_rate=0.2, ondevice_rate=0.5, long_meeting_rate=0.25)
    c = cm.calls_per_user(u)
    assert c["translate"] == pytest.approx(100 * 0.9 * 0.8 * 0.5)
    assert c["meeting"] == 4 and c["summary"] == 1


def test_free_limit_rpd_binds() -> None:
    m = cm.ModelPrice("m", free_rpd=100, free_rpm=1000)
    free, binding = cm.free_calls_per_day(m, calls_per_day=150, peak_factor=5)
    assert free == 100 and binding == "rpd"
    free, binding = cm.free_calls_per_day(m, calls_per_day=50, peak_factor=5)
    assert free == 50 and binding == "none"


def test_free_limit_rpm_binds_before_rpd() -> None:
    # 1440건/일 → 평균 1 RPM, 피크 5배 = 5 RPM > free_rpm 2 → 2/5 만 무료
    m = cm.ModelPrice("m", free_rpd=10_000, free_rpm=2)
    free, binding = cm.free_calls_per_day(m, calls_per_day=1440, peak_factor=5)
    assert binding == "rpm" and free == pytest.approx(1440 * 2 / 5)


def test_bill_models_fallback_moves_overflow(pricing: cm.Pricing) -> None:
    vols = [cm.CallVolume("translate", "gemini_free", calls=30_000, input_tokens=1e6, cached_tokens=0, output_tokens=1e6)]
    bills = {b.model_id: b for b in cm.bill_models(vols, pricing, peak_factor=1.0)}
    g = bills["gemini_free"]
    assert g.free_calls == 200 * 30 and g.billable_calls == 30_000 - 6_000 and g.usd == 0.0
    assert bills["none"].calls == pytest.approx(24_000)  # 초과분이 none 으로 이동


def test_bill_models_pay_uses_token_prices(pricing: cm.Pricing) -> None:
    vols = [cm.CallVolume("translate", "paid_example", calls=10, input_tokens=1e6, cached_tokens=2e6, output_tokens=0.5e6)]
    (b,) = cm.bill_models(vols, pricing, peak_factor=5.0)
    assert b.usd == pytest.approx(1 * 2.0 + 2 * 1.0 + 0.5 * 8.0)
    assert b.binding_limit == "no_free" and not b.unpriced


def test_bill_models_degrade_drops(pricing: cm.Pricing) -> None:
    vols = [cm.CallVolume("translate", "degrade_example", calls=6_000, input_tokens=0, cached_tokens=0, output_tokens=0)]
    (b,) = cm.bill_models(vols, pricing, peak_factor=1.0)
    assert b.dropped_calls == pytest.approx(3_000) and b.usd == 0.0


def test_stt_chain_selfhost_capacity_then_external(pricing: cm.Pricing) -> None:
    oci = pricing.scenarios["oci_free"]  # 4 vcpu × 43200 × 0.7 = 120,960 CPU분 → 2.0 CPU분/오디오분 → 60,480 오디오분
    bills, dropped = cm.bill_stt(100_000, pricing, oci)
    assert [b.stage for b in bills] == ["whisper_local", "external_example"]
    assert bills[0].minutes == pytest.approx(60_480) and bills[0].selfhost and bills[0].usd == 0.0
    ext = bills[1]
    assert ext.minutes == pytest.approx(39_520) and ext.free_minutes == pytest.approx(1_800)
    assert ext.usd == pytest.approx((39_520 - 1_800) * 0.01)
    assert dropped == 0.0
    # AWS: 2 vcpu → 30,240 분, VM 배분액 = CPU분 × (15 / (2×43200))
    aws = pricing.scenarios["aws_t4g_small"]
    bills, _ = cm.bill_stt(10_000, pricing, aws)
    assert bills[0].usd == pytest.approx(10_000 * 2.0 * 15 / (2 * 43_200))


def test_stt_chain_reports_dropped_when_exhausted() -> None:
    p = cm.load_pricing(EXAMPLE)
    only_local = cm.Pricing(**{**p.__dict__, "stt_chain": p.stt_chain[:1]})
    bills, dropped = cm.bill_stt(100_000, only_local, p.scenarios["oci_free"])
    assert dropped == pytest.approx(100_000 - 60_480)


def test_storage_free_gb(pricing: cm.Pricing) -> None:
    u = cm.UsageProfile(recording_minutes=120)
    usd, unpriced = cm.storage_usd(1000, u, pricing)
    gb = 120_000 / 1024
    assert usd == pytest.approx((gb - 10) * 0.015) and not unpriced
    usd, _ = cm.storage_usd(10, u, pricing)
    assert usd == 0.0  # 1.2GB < 10GB 무료


def test_estimate_total_excludes_selfhost_allocation(pricing: cm.Pricing, usage: cm.UsageProfile) -> None:
    r = cm.estimate(1000, usage, pricing, "gemini_free", "aws_t4g_small")
    assert r.total_usd == pytest.approx(r.ai_usd + r.stt_usd + r.storage_usd + r.fixed_usd)
    assert r.stt_selfhost_allocated_usd > 0
    assert r.per_mau_krw == pytest.approx(r.total_krw / 1000)
    assert r.variable_per_mau_krw == pytest.approx((r.total_usd - r.fixed_usd) * 1000 / 1000)


def test_breakeven_price_formula() -> None:
    r = cm.CostReport("t", "s", mau=1000, ai_usd=0, stt_usd=0, stt_selfhost_allocated_usd=0, storage_usd=0, fixed_usd=0,
                      total_usd=100, total_krw=100_000, per_mau_krw=100, variable_per_mau_krw=100)
    be = cm.breakeven_price_krw(r, conversion=0.05, margin=0.5, store_fee=0.15, vat=0.10)
    assert be["payers"] == 50
    assert be["list_price_breakeven"] == pytest.approx(100_000 / 50 / 0.85 * 1.1)
    assert be["list_price_target_margin"] == pytest.approx(200_000 / 50 / 0.85 * 1.1)


def test_free_limit_mau(pricing: cm.Pricing) -> None:
    u = cm.UsageProfile(translations=30, peak_factor=5.0)  # 1인 1일 1건
    f = cm.free_limit_mau("gemini_free", u, pricing)
    assert f["mau_rpd"] == pytest.approx(200)
    assert f["mau_rpm"] == pytest.approx(10 / (1 / 1440 * 5))
    assert f["binding"] == "rpd"
    assert cm.free_limit_mau("paid_example", u, pricing)["mau_rpd"] == math.inf


def test_unverified_pricing_yields_warnings_not_numbers(usage: cm.UsageProfile) -> None:
    p = cm.load_pricing(EVAL / "pricing.toml")
    r = cm.estimate(1000, usage, p, "openai_key", "oci_free")
    assert r.total_krw == 0.0
    assert any("단가 미확인" in w for w in r.warnings)
    assert any("CPU 분 미실측" in w for w in r.warnings)


def test_cli_md_and_json(capsys: pytest.CaptureFixture[str]) -> None:
    assert cm.main(["--mau", "500", "--pricing", str(EXAMPLE), "--usage", str(USAGE)]) == 0
    out = capsys.readouterr().out
    assert "| 트랙 |" in out and "무료 한도 소진 MAU" in out and "가정값" not in out
    assert cm.main(["--mau", "500", "--pricing", str(EXAMPLE), "--usage", str(USAGE), "--format", "json", "--scenario", "aws_t4g_small"]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert {r["track"] for r in payload["reports"]} == set(cm.load_pricing(EXAMPLE).tracks)
    assert payload["reports"][0]["scenario"] == "aws_t4g_small"
