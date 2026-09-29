FROM ghcr.io/astral-sh/uv:0.12.20@sha256:100047e74f30778ab704942321a09750d6158739573ff58bf3924085cc6cd2d8 AS uv

FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS dependencies

ENV UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app
COPY --from=uv /uv /uvx /bin/
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv lock --check \
    && uv sync --frozen --no-dev --no-install-project

FROM python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01 AS runtime

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

# Package managers and build tooling are unnecessary at runtime. Resolve their
# locations dynamically so Python minor-version updates cannot bypass cleanup.
RUN set -eux; \
    stdlib="$(/usr/local/bin/python -c 'import sysconfig; print(sysconfig.get_path("stdlib"))')"; \
    purelib="$(/usr/local/bin/python -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"; \
    rm -rf \
      "${stdlib}/ensurepip" \
      "${purelib}/_distutils_hack" \
      "${purelib}"/pip* \
      "${purelib}"/setuptools*; \
    rm -f /usr/local/bin/pip*; \
    if /usr/local/bin/python -c 'import pip' 2>/dev/null; then \
      echo 'pip must not be present in the runtime image' >&2; \
      exit 1; \
    fi; \
    if /usr/local/bin/python -c 'import setuptools' 2>/dev/null; then \
      echo 'setuptools must not be present in the runtime image' >&2; \
      exit 1; \
    fi

WORKDIR /app
COPY --from=dependencies /app/.venv /app/.venv
COPY --chown=10001:10001 app/ /app/app/

ENV PATH="/app/.venv/bin:${PATH}"

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=3s --retries=3 \
  CMD ["python", "-c", "from urllib.request import urlopen; urlopen('http://127.0.0.1:8080/healthz', timeout=2)"]

ENTRYPOINT ["gunicorn"]
CMD ["--bind=0.0.0.0:8080", "--workers=1", "--threads=4", "--worker-tmp-dir=/dev/shm", "--no-control-socket", "--timeout=30", "--graceful-timeout=10", "--access-logfile=-", "--error-logfile=-", "app.main:app"]
