FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN pip install --no-cache-dir uv
WORKDIR /srv
COPY services/api/pyproject.toml services/api/uv.lock* ./
RUN uv sync --frozen --no-dev --no-install-project || uv sync --no-dev --no-install-project
COPY services/api/app ./app
COPY contracts /contracts
ENV MWONMAL_CONTRACT_PATH=/contracts/openapi.yml
RUN useradd -m app && chown -R app /srv
USER app
EXPOSE 8080
HEALTHCHECK CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/ready')" || exit 1
CMD ["/srv/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "2"]
