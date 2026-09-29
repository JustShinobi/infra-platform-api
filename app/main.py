"""Flask application for the Infra Platform API."""

from __future__ import annotations

import os
import socket
from http import HTTPStatus
from typing import Any

from flask import Flask, Response, jsonify


APP_NAME = "infra-platform-api"


def health_payload() -> dict[str, str]:
    """Return the process health representation."""
    return {"status": "ok"}


def info_payload() -> dict[str, str]:
    """Return runtime metadata, including configuration injected by Kubernetes."""
    return {
        "application": APP_NAME,
        "version": os.getenv("APP_VERSION", "dev"),
        "environment": os.getenv("APP_ENV", "local"),
        "message": os.getenv("APP_MESSAGE", "running locally"),
        "hostname": socket.gethostname(),
    }


def create_app() -> Flask:
    """Create the Flask application without global configuration side effects."""
    application = Flask(__name__)

    @application.after_request
    def add_security_headers(response: Response) -> Response:
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'"
        )
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @application.get("/healthz")
    def health() -> tuple[Response, int]:
        return jsonify(health_payload()), HTTPStatus.OK

    @application.get("/info")
    def info() -> tuple[Response, int]:
        return jsonify(info_payload()), HTTPStatus.OK

    @application.errorhandler(HTTPStatus.NOT_FOUND)
    def not_found(_error: Any) -> tuple[Response, int]:
        return jsonify({"error": "not found"}), HTTPStatus.NOT_FOUND

    return application


app = create_app()


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "8080")), debug=False)
