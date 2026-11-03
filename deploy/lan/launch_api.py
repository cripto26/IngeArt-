"""Launch from the bundled interpreter without a Windows venv child launcher."""
from pathlib import Path
import os
import site
import sys

root = Path(__file__).resolve().parent
backend = root / "backend"
site.addsitedir(str(backend / ".venv" / "Lib" / "site-packages"))
sys.path.insert(0, str(backend))
os.chdir(backend)
from dotenv import load_dotenv
load_dotenv(backend / ".env", override=True)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="127.0.0.1", port=8010,
                proxy_headers=False, access_log=False)
