FROM python:3.13-alpine@sha256:79e7a9b9ff1cbceff819f856fb374477792a5967759d94df266de7b7b4120e6f AS dependencies

COPY requirements.lock /tmp/requirements.lock
RUN python -m pip install \
      --disable-pip-version-check \
      --no-cache-dir \
      --require-hashes \
      --prefix=/install \
      -r /tmp/requirements.lock

FROM python:3.13-alpine@sha256:79e7a9b9ff1cbceff819f856fb374477792a5967759d94df266de7b7b4120e6f AS runtime

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app
COPY --from=dependencies /install /usr/local
COPY --chown=10001:10001 app/ /app/app/

# Package managers and build tooling are unnecessary at runtime. Removing them
# reduces the attack surface and excludes their vendored dependencies.
RUN rm -rf \
      /usr/local/lib/python3.13/ensurepip \
      /usr/local/lib/python3.13/site-packages/_distutils_hack \
      /usr/local/lib/python3.13/site-packages/pip* \
      /usr/local/lib/python3.13/site-packages/setuptools* \
    && rm -f /usr/local/bin/pip*

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=3s --retries=3 \
  CMD ["python", "-c", "from urllib.request import urlopen; urlopen('http://127.0.0.1:8080/healthz', timeout=2)"]

ENTRYPOINT ["gunicorn"]
CMD ["--bind=0.0.0.0:8080", "--workers=1", "--threads=4", "--worker-tmp-dir=/dev/shm", "--no-control-socket", "--timeout=30", "--graceful-timeout=10", "--access-logfile=-", "--error-logfile=-", "app.main:app"]
