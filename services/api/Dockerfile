FROM python:3.12-slim AS base
# 2026-10-26 레드팀: 이미지 기본 env = prod (fail-closed). 설정을 빠뜨리면 JWT 임시 키로 조용히 뜨지
# 않고 기동이 실패한다. 로컬 Compose 는 MWONMAL_ENV=local 을 명시한다.
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    MWONMAL_ENV=prod WEB_CONCURRENCY=2 \
    UV_NO_CACHE=1 UV_COMPILE_BYTECODE=0
# uv 버전 고정(빌드 재현성·공급망). 올릴 땐 이 줄만 바꾼다.
RUN pip install --no-cache-dir "uv==0.12.13"
WORKDIR /srv
COPY services/api/pyproject.toml services/api/uv.lock ./
# 잠금 파일 그대로만 설치한다. 실패하면 빌드 실패(예전엔 `|| uv sync` 로 잠금을 무시하고 새로 풀었다).
RUN uv sync --frozen --no-dev --no-install-project
COPY services/api/app ./app
COPY services/api/alembic.ini ./alembic.ini
COPY services/api/migrations ./migrations
COPY contracts /contracts
ENV MWONMAL_CONTRACT_PATH=/contracts/openapi.yml
# 코드·venv 는 root 소유(읽기 전용)로 두고 실행만 비root. 예전엔 chown -R app /srv 로
# 앱 프로세스가 자기 코드를 고쳐 쓸 수 있었다.
RUN useradd --create-home --uid 10001 app
USER app
EXPOSE 8080
HEALTHCHECK CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/ready')" || exit 1
# 워커 수는 WEB_CONCURRENCY(uvicorn 기본 지원). local 은 1(임시 JWT 키가 워커마다 다르다).
# --http h11: httptools 는 요청 헤더 크기 한도가 없어 100MB 헤더 하나로 워커 RSS 가 GB 단위로
# 늘었다(레드팀 R2). h11 은 헤더를 16KB 로 자른다. Caddy 를 거치지 않는 경로에서도 막힌다.
CMD ["/srv/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-server-header", "--http", "h11"]
