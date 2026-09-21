.PHONY: setup generate build-ios build-mac test lint fmt server-up server-test cost eval eval-test
MAU ?= 1000
SCENARIO ?= oci_free
ENGINE ?= none
LIMIT ?= 50
setup: ; mise install && cd services/api && uv sync
generate: ; cd apps/ios-macos && tuist install && tuist generate --no-open
build-ios: generate ; cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalIOS -destination 'generic/platform=iOS Simulator' build | tail -3
build-mac: generate ; cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalMac -destination 'platform=macOS' build | tail -3
test: ; cd apps/ios-macos && tuist test MwonmalMac --no-selective-testing
lint: ; swiftlint --strict && swiftformat --lint . && cd services/api && uv run ruff check . && uv run mypy .
fmt: ; swiftformat . && cd services/api && uv run ruff format .
server-up: ; docker compose -f infra/docker-compose.yml up -d --wait
server-test: ; cd services/api && uv run pytest -q
# FD-6 / ADR-0009: MAU당 월 원가 (pricing.toml 미확인 항목은 경고로 표시)
cost: ; python3 eval/cost_model.py --mau $(MAU) --scenario $(SCENARIO)
# FD-5 / ADR-0007: 평가 하네스 (CI 외부 호출 0 → 기본 ENGINE=none, 캐시 적중분만)
eval: ; python3 eval/run.py --engine $(ENGINE) --limit $(LIMIT)
eval-test: ; uv run --python 3.14 --with pytest --no-project python -m pytest eval/tests -q
