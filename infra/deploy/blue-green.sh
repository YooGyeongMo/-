#!/usr/bin/env bash
# 블루·그린 배포 (ADR-0003). 사용: API_TAG=sha ./blue-green.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ACTIVE=$(curl -fsS localhost:2019/config/apps/http/servers/srv0/routes/0/handle/0/upstreams/0/dial | tr -d '"' | cut -d: -f1)
[[ "$ACTIVE" == "api_blue" ]] && NEW=api_green || NEW=api_blue
echo "active=$ACTIVE new=$NEW tag=${API_TAG:?}"
docker compose pull "$NEW"
docker compose --profile green up -d --no-deps "$NEW"
for i in $(seq 1 30); do
  docker compose exec -T "$NEW" python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/ready')" && break
  sleep 2; [[ $i == 30 ]] && { echo "ready 실패, 롤백(전환 안 함)"; docker compose stop "$NEW"; exit 1; }
done
curl -fsS -X PATCH localhost:2019/config/apps/http/servers/srv0/routes/0/handle/0/upstreams/0/dial -H 'Content-Type: application/json' -d "\"$NEW:8080\""
echo "전환 완료 → $NEW. 30초 drain 후 $ACTIVE 정지"
sleep 30
docker compose stop "$ACTIVE"
