"""인프라·CI 설정 회귀 가드 (레드팀 2026-10-26, docs/lessons/2026-10-26-server-redteam.md)."""

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
CADDY = (ROOT / "infra" / "Caddyfile").read_text(encoding="utf-8")
DOCKERFILE = (ROOT / "services" / "api" / "Dockerfile").read_text(encoding="utf-8")
COMPOSE = yaml.safe_load((ROOT / "infra" / "docker-compose.yml").read_text(encoding="utf-8"))
WORKFLOWS = sorted((ROOT / ".github" / "workflows").glob("*.yml"))


def _code_lines(text: str) -> list[str]:
    return [ln.split("#", 1)[0].strip() for ln in text.splitlines() if ln.split("#", 1)[0].strip()]


def test_caddy_admin_api_is_loopback_only() -> None:
    admin = [ln for ln in _code_lines(CADDY) if ln.startswith("admin")]
    assert admin == ["admin localhost:2019"]


def test_caddy_limits_body_and_sets_security_headers() -> None:
    assert "max_size" in CADDY
    for h in ("X-Content-Type-Options nosniff", "-Server", "frame-ancestors 'none'"):
        assert h in CADDY


def test_caddy_admin_port_never_published() -> None:
    for name, svc in COMPOSE["services"].items():
        for port in svc.get("ports", []):
            assert "2019" not in str(port), name


def test_database_and_redis_not_published() -> None:
    for name in ("mysql", "redis"):
        assert "ports" not in COMPOSE["services"][name]


def test_local_api_runs_single_worker() -> None:
    # local 은 JWT 임시 키가 워커마다 달라 워커가 2개면 토큰이 무작위로 401.
    for name in ("api_blue", "api_green"):
        env = COMPOSE["services"][name]["environment"]
        assert env["MWONMAL_ENV"] == "${MWONMAL_ENV:-local}"
        assert env["WEB_CONCURRENCY"] == "${WEB_CONCURRENCY:-1}"


def test_dockerfile_is_fail_closed_and_locked() -> None:
    code = "\n".join(_code_lines(DOCKERFILE))
    assert "MWONMAL_ENV=prod" in code
    assert "uv sync --frozen" in code and "|| uv sync" not in code
    assert re.search(r"uv==\d+\.\d+\.\d+", code)
    assert "chown" not in code  # 코드는 root 소유, 앱 사용자는 실행만
    assert "USER app" in code
    assert "--workers" not in code  # WEB_CONCURRENCY 로만
    assert '"--http", "h11"' in code  # 헤더 크기 한도


def test_workflows_least_privilege_and_pinned() -> None:
    for wf in WORKFLOWS:
        text = wf.read_text(encoding="utf-8")
        doc = yaml.safe_load(text)
        assert doc.get("permissions") == {"contents": "read"}, wf.name
        assert "pull_request_target" not in text, wf.name
        for uses in re.findall(r"uses:\s*(\S+)", text):
            assert re.fullmatch(r"[\w.-]+/[\w./-]+@[0-9a-f]{40}", uses), f"{wf.name}: {uses}"
        # run 스크립트에 github.event 값을 직접 끼워 넣지 않는다(스크립트 주입).
        for job in doc["jobs"].values():
            for step in job.get("steps", []):
                assert "github.event" not in str(step.get("run", "")), wf.name


def test_contract_job_is_not_masked() -> None:
    text = (ROOT / ".github" / "workflows" / "server.yml").read_text(encoding="utf-8")
    contract = text.split("  contract:")[1].split("\n  image:")[0]
    assert "|| true" not in _code_lines(contract).__str__()
    assert "schemathesis run" in contract
