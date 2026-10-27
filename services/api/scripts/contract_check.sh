#!/usr/bin/env bash
# 계약 검사(schemathesis): 개발 서버(SQLite + 개발용 로그인)를 띄우고 로그인 토큰으로 성공 경로까지 본다(#110).
# CI server.yml contract job 과 로컬에서 같은 명령을 쓴다.  사용: scripts/contract_check.sh [max-examples]
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8090}"
DB="$(mktemp -d)/contract.db"
MWONMAL_ENV=test uv run python scripts/dev_server.py --db "$DB" --port "$PORT" > /tmp/mw-contract-server.log 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break; sleep 1; done
TOKEN=$(curl -fsS -X POST "http://127.0.0.1:$PORT/api/auth/oauth/apple" -H 'content-type: application/json' \
  -d '{"code":"dev:contract","redirectUri":"x"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["accessToken"])')
OPS=(oauthLogin getMe createTranslation getTranslations getTranslation deleteTranslation updateAction getActions getTerm getProjects getProject)
ARGS=()
for op in "${OPS[@]}"; do ARGS+=(--include-operation-id "$op"); done
uv run schemathesis run "http://127.0.0.1:$PORT/openapi.json" --url "http://127.0.0.1:$PORT/api" \
  --checks all --exclude-checks allow_header_conformance \
  --max-examples="${1:-100}" -H "Authorization: Bearer $TOKEN" "${ARGS[@]}"
