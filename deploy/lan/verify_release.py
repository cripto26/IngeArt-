from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
manifest = json.loads((root / "RELEASE.json").read_text(encoding="utf-8"))
for name, expected in manifest["files_sha256"].items():
    path = (root / name).resolve()
    if not path.is_relative_to(root) or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit("El paquete fue modificado: " + name)
public = {p.relative_to(root).as_posix() for p in (root / "frontend").rglob("*") if p.is_file()}
if public != {name for name in manifest["files_sha256"] if name.startswith("frontend/")}:
    raise SystemExit("Hay archivos publicos ajenos al artefacto validado.")
print("Package integrity verified.")
