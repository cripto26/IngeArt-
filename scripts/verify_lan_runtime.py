"""Probe the real LAN release with certificate verification and no DB writes."""
import hashlib
import json
from pathlib import Path
import ssl
from urllib.error import HTTPError
from urllib.request import build_opener, HTTPSHandler, ProxyHandler, Request, HTTPRedirectHandler

ROOT = Path(__file__).resolve().parents[1]
LAN = Path(r"D:\Ingear-caddy- local")
REPORT = ROOT / "entregables/preparacion_despliegue_2026-11-03/lan-verification.json"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None


def main():
    certificate = LAN / "caddy-data/caddy/pki/authorities/local/root.crt"
    context = ssl.create_default_context(cafile=str(certificate))
    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=context), NoRedirect())
    def get(url, *, data=None, headers=None):
        request = Request(url, data=data, headers=headers or {})
        try:
            response = opener.open(request, timeout=10)
        except HTTPError as error:
            response = error
        with response:
            return response.status, dict(response.headers), response.read()

    release = json.loads((LAN / "RELEASE.json").read_text(encoding="utf-8"))
    checks = {}
    status, headers, body = get("https://localhost/")
    checks["https_localhost"] = status == 200 and b'<div id="root"></div>' in body
    checks["security_headers"] = all(name in {key.lower() for key in headers}
        for name in ("content-security-policy", "x-content-type-options", "x-frame-options", "permissions-policy", "referrer-policy"))
    for host in ("127.0.0.1", "192.168.1.152"):
        status, _, body = get(f"https://{host}/health/ready")
        health = json.loads(body)
        checks[f"verified_tls_and_readiness_{host}"] = status == 200 and health["ok"] and health["version"] == release["source_commits"]["backend"]
    status, headers, body = get("https://localhost/health/ready")
    checks["api_not_cached"] = headers.get("Cache-Control", "").lower() == "no-store"
    status, _, body = get("https://localhost/api/v1/nonexistent-release-probe")
    checks["api_404_is_json"] = status == 404 and json.loads(body).get("detail") == "Not Found"
    status, _, body = get("https://localhost/ajustes")
    checks["spa_navigation"] = status == 200 and b'<div id="root"></div>' in body
    status, _, body = get("https://localhost/backend/.env")
    checks["private_configuration_not_served"] = b"SECRET_KEY=" not in body and b'<div id="root"></div>' in body
    status, headers, _ = get("http://localhost/")
    checks["http_redirects_to_https"] = status in (301, 302, 307, 308) and headers.get("Location", "").startswith("https://")
    status, _, _ = get("https://localhost/api/v1/productos/1/imagen", data=b"x",
                       headers={"Content-Length": str(33 * 1024 * 1024), "Content-Type": "application/octet-stream"})
    checks["oversized_request_rejected"] = status == 413
    status, _, body = get("https://localhost/", headers={"Host": "unconfigured.example.test"})
    checks["unknown_host_not_served"] = status in (403, 404, 421) or (status == 200 and not body)
    mismatches = []
    for source in (ROOT / "API_Ingear/app").rglob("*.py"):
        target = LAN / "backend/app" / source.relative_to(ROOT / "API_Ingear/app")
        if not target.is_file() or source.read_bytes() != target.read_bytes(): mismatches.append(str(source.relative_to(ROOT)))
    checks["backend_matches_source"] = not mismatches
    for source in (ROOT / "Front_Ingear/dist").rglob("*"):
        if source.is_file():
            target = LAN / "frontend" / source.relative_to(ROOT / "Front_Ingear/dist")
            if not target.is_file() or source.read_bytes() != target.read_bytes(): mismatches.append(str(source.relative_to(ROOT)))
    checks["frontend_matches_build"] = not mismatches
    objects, total = 0, 0
    for source in (ROOT / "API_Ingear/exports").rglob("*"):
        relative = source.relative_to(ROOT / "API_Ingear/exports")
        target = LAN / "backend/exports" / relative
        if source.is_file() and target.is_file():
            objects += 1
            total += source.stat().st_size
            if hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(target.read_bytes()).digest(): mismatches.append("operational object")
    checks["operational_files_match"] = objects > 0 and not mismatches
    checks["no_development_packages"] = not any((LAN / "backend/.venv/Lib/site-packages").glob("pytest*"))
    checks["no_git_or_node_modules"] = not any(path.name in {".git", "node_modules"} for path in LAN.rglob("*"))
    result = {"ok": all(checks.values()), "checks": checks, "operational_files": objects,
        "operational_bytes": total, "source_commits": release["source_commits"],
        "tls_root_sha256": hashlib.sha256(ssl.PEM_cert_to_DER_cert(certificate.read_text())).hexdigest(),
        "real_user_login_tested": False, "business_database_writes": False}
    REPORT.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
