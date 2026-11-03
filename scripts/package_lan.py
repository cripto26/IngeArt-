"""Create the private LAN runtime from the validated Google Cloud source tree.

Destination must be empty. No Git history, development environment, tests,
node_modules or temporary reports are copied. Existing LAN credentials and
documents are copied privately. The existing LAN database is reused; this
command never migrates or alters it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
API = ROOT / "API_Ingear"
FRONT = ROOT / "Front_Ingear"
sys.path.insert(0, str(API))


def copy_file(source, target):
    if source.is_symlink():
        raise RuntimeError("No se empaquetan enlaces simbolicos.")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def copy_tree(source, target):
    for path in source.rglob("*"):
        if path.is_file() and "__pycache__" not in path.parts and path.suffix not in {".pyc", ".pyo"}:
            copy_file(path, target / path.relative_to(source))


def main():
    os.chdir(API)
    from app.core.config import settings
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--caddy", type=Path, required=True)
    args = parser.parse_args()
    target = args.destination.resolve()
    if str(target).lower() != r"D:\Ingear-caddy- local".lower():
        parser.error("El destino debe ser la carpeta LAN autorizada.")
    if target.exists() and any(target.iterdir()):
        parser.error("El destino no esta vacio; se conserva su contenido.")
    build = json.loads((FRONT / "dist/build-configuration.json").read_text(encoding="utf-8"))
    if build["deploymentTarget"] != "lan" or not build["bypass"]:
        parser.error("Compila primero el frontend LAN real con bypass privado explicito.")
    if any((FRONT / "dist").rglob("*.pdf")):
        parser.error("El frontend contiene documentos PDF; reconstruir con la politica de recursos publicos.")
    for repository in (API, FRONT):
        if subprocess.check_output(["git", "status", "--porcelain"], cwd=repository, text=True).strip():
            parser.error("Empaquetar unicamente commits fuente limpios y revisados.")
    toolchain = json.loads((FRONT / "deployment-toolchain.json").read_text(encoding="utf-8"))
    caddy_version = subprocess.check_output([str(args.caddy), "version"], text=True).split()[0]
    if caddy_version != "v" + toolchain["caddy"]:
        parser.error("Usar la version de Caddy fijada en deployment-toolchain.json.")
    target.mkdir(parents=True, exist_ok=True)
    for template in (ROOT / "deploy/lan").iterdir():
        if template.is_file() and (template.name == "Caddyfile" or template.suffix in {".py", ".ps1", ".cmd", ".md"}):
            copy_file(template, target / template.name)
    copy_tree(API / "app", target / "backend/app")
    for name in (".python-version", "requirements.in", "requirements-dev.in", "requirements.txt",
                 "requirements-dev.txt", "requirements.lock.json", "migration-baseline-inputs.json"):
        copy_file(API / name, target / "backend" / name)
    for name in ("verify_environment.py", "bootstrap_backend.ps1", "check_migration_inputs.py"):
        copy_file(API / "scripts" / name, target / "backend/scripts" / name)
    copy_tree(API / ".tools/python-3.14.8/tools", target / "backend/.tools/python-3.14.8/tools")
    copy_tree(FRONT / "dist", target / "frontend")
    copy_file(args.caddy, target / "bin/caddy.exe")
    operational = ("contratos", "cuentas_cobro", "facturas", "polizas", "logistica-ordenes-pedido-documentos",
                   "proyecto_remisiones", "product_images")
    for name in operational:
        if (API / "exports" / name).is_dir():
            copy_tree(API / "exports" / name, target / "backend/exports" / name)
    credential = Path(settings.GOOGLE_SERVICE_ACCOUNT_FILE)
    if not credential.is_absolute():
        credential = API / credential
    if credential.is_file():
        copy_file(credential, target / "backend/credentials/google-service-account.json")
    versions = {name: subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=path, text=True).strip()
                for name, path in (("backend", API), ("frontend", FRONT))}
    values = settings.model_dump(exclude_none=True)
    values.update(APP_ENV="development", APP_VERSION=versions["backend"],
        PUBLIC_APP_ORIGIN="https://192.168.1.152", BACKEND_PROXY_MODE="direct", CORS_ALLOWED_ORIGINS="",
        RUN_REMINDER_SCHEDULER=False, FILE_STORAGE_BACKEND="local", CLIENT_IP_MODE="trusted-cidrs",
        TRUSTED_PROXY_CIDRS="127.0.0.1/32,::1/128", GOOGLE_SERVICE_ACCOUNT_FILE="credentials/google-service-account.json",
        REFRESH_COOKIE_NAME="ingear_refresh_token", REFRESH_COOKIE_SECURE=True,
        REFRESH_COOKIE_DOMAIN="", TURNSTILE_ENABLED=True, TURNSTILE_DEV_BYPASS=True,
        TURNSTILE_SECRET_KEY="", WORLD_OFFICE_ENABLED=False, WORLD_OFFICE_ENCRYPT=True, WORLD_OFFICE_TRUST_SERVER_CERTIFICATE=False)
    for name in ("K_SERVICE", "K_REVISION", "GCS_BUCKET_NAME", "GCS_PROJECT_ID"):
        values.pop(name, None)
    def env_value(value):
        return json.dumps(str(value).lower() if isinstance(value, bool) else str(value), ensure_ascii=True)
    (target / "backend/.env").write_text("\n".join(f"{name}={env_value(value)}" for name, value in sorted(values.items()))+"\n", encoding="utf-8")
    files = {}
    for path in sorted(target.rglob("*")):
        relative = path.relative_to(target).as_posix()
        if path.is_file() and not relative.startswith(("backend/credentials/", "backend/exports/", "backend/.tools/", "logs/", "caddy-data/", "caddy-config/")) and relative not in {"backend/.env", "Caddyfile"}:
            files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    (target / "RELEASE.json").write_text(json.dumps({"target": "LAN-Caddy", "caddy_version": caddy_version, "source_commits": versions,
        "frontend_configuration": build, "private_configuration": "backend/.env",
        "mutable_configuration": ["Caddyfile", "backend/.env"],
        "database": "Existing local database, unchanged by packaging", "files_sha256": files}, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"destination": str(target), "source_commits": versions, "public_files_verified": len(files)}))


if __name__ == "__main__":
    main()
