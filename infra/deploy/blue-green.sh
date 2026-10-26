#!/usr/bin/env bash
# 블루·그린 배포 (ADR-0003). 사용: API_TAG=sha ./blue-green.sh
#
# 2026-10-26 레드팀 개정:
#  - Caddy 관리 API 는 컨테이너 루프백에만 열린다(Caddyfile). 호스트 curl localhost:2019 는 원래도
#    포트가 publish 되지 않아 닿지 않았고, JSON 경로(handle/0)도 headers 핸들러를 가리켜 틀렸다.
#  - 전환 = MW_UPSTREAM 환경변수로 Caddyfile 을 다시 적용(`caddy reload`, 컨테이너 안에서 실행).
#    활성 색은 infra/.upstream 에 남겨 Caddy 컨테이너가 재시작돼도 유지된다.
set -euo pipefail
cd "$(dirname "$0")/.."
STATE=.upstream
ACTIVE=api_blue
if [[ -f "$STATE" ]]; then
  ACTIVE=$(sed -n 's/^MW_UPSTREAM=\(api_[a-z]*\):8080$/\1/p' "$STATE")
fi
[[ "$ACTIVE" == "api_blue" || "$ACTIVE" == "api_green" ]] || { echo "알 수 없는 활성 색: $ACTIVE"; exit 1; }
[[ "$ACTIVE" == "api_blue" ]] && NEW=api_green || NEW=api_blue
echo "active=$ACTIVE new=$NEW tag=${API_TAG:?}"
docker compose pull "$NEW"
docker compose --profile green up -d --no-deps "$NEW"
for i in $(seq 1 30); do
  docker compose exec -T "$NEW" python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/ready')" && break
  sleep 2; [[ $i == 30 ]] && { echo "ready 실패, 롤백(전환 안 함)"; docker compose stop "$NEW"; exit 1; }
done
docker compose exec -T -e "MW_UPSTREAM=$NEW:8080" caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
echo "MW_UPSTREAM=$NEW:8080" > "$STATE"
echo "전환 완료 → $NEW. 30초 drain 후 $ACTIVE 정지"
sleep 30
docker compose stop "$ACTIVE"
