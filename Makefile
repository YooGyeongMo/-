.PHONY: setup generate build-ios build-mac test lint fmt server-up server-test
setup: ; mise install && cd services/api && uv sync
generate: ; cd apps/ios-macos && tuist install && tuist generate --no-open
build-ios: generate ; cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalIOS -destination 'generic/platform=iOS Simulator' build | tail -3
build-mac: generate ; cd apps/ios-macos && xcodebuild -workspace Mwonmal.xcworkspace -scheme MwonmalMac -destination 'platform=macOS' build | tail -3
test: ; cd apps/ios-macos && tuist test MwonmalMac
lint: ; swiftlint --strict && swiftformat --lint . && cd services/api && uv run ruff check . && uv run mypy .
fmt: ; swiftformat . && cd services/api && uv run ruff format .
server-up: ; docker compose -f infra/docker-compose.yml up -d --wait
server-test: ; cd services/api && uv run pytest -q
