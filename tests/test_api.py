from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from flask.testing import FlaskClient

from app.main import create_app, health_payload, info_payload


class PayloadTests(unittest.TestCase):
    def test_health_payload(self) -> None:
        self.assertEqual(health_payload(), {"status": "ok"})

    def test_info_payload_reads_environment(self) -> None:
        environment = {
            "APP_VERSION": "1.2.3",
            "APP_ENV": "test",
            "APP_MESSAGE": "configured by test",
        }
        with patch.dict(os.environ, environment, clear=True):
            payload = info_payload()

        self.assertEqual(payload["version"], "1.2.3")
        self.assertEqual(payload["environment"], "test")
        self.assertEqual(payload["message"], "configured by test")
        self.assertTrue(payload["hostname"])


class EndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        application = create_app()
        application.config.update(TESTING=True)
        self.client: FlaskClient = application.test_client()

    def test_health_endpoint(self) -> None:
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "ok"})
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertEqual(
            response.headers["Content-Security-Policy"],
            "default-src 'none'; frame-ancestors 'none'",
        )
        self.assertEqual(response.headers["Referrer-Policy"], "no-referrer")
        self.assertEqual(response.headers["X-Content-Type-Options"], "nosniff")

    def test_info_endpoint(self) -> None:
        with patch.dict(os.environ, {"APP_ENV": "integration"}):
            response = self.client.get("/info")
        payload = response.get_json()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(payload["application"], "infra-platform-api")
        self.assertEqual(payload["environment"], "integration")
        self.assertTrue(payload["hostname"])

    def test_unknown_endpoint_returns_json(self) -> None:
        response = self.client.get("/unknown")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.get_json(), {"error": "not found"})


if __name__ == "__main__":
    unittest.main()
