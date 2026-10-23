"""Installs the requirements that are not installed yet, and only those.

    python scripts/pip_missing.py

Run from cPanel's "Execute python script" box, which accepts a Python file
and nothing else - so this works on a host with no shell.

**Why not just run pip on the whole file?** Because that is what keeps
failing here. This host kills a long-running process, and installing forty
packages over a slow link takes long enough to be killed every time - always
somewhere around the compiled ones (cffi, cryptography, bcrypt), which are
the biggest and come late. Each attempt leaves the virtualenv a little
further along and no closer to finished.

So this asks what is *actually* missing and installs that much, which on the
second run is a handful of packages and finishes inside the limit. Run it
again if it is killed again: it picks up where it left off, and says what is
still outstanding.
"""

import importlib.util
import subprocess
import sys
from pathlib import Path

REQUIREMENTS = Path(__file__).resolve().parent.parent / "backend-python" / "requirements.txt"

# A handful of distributions import under a different name than they install
# under. Anything not listed here is assumed to match.
IMPORT_NAMES = {
    "django-cors-headers": "corsheaders",
    "djangorestframework": "rest_framework",
    "factory-boy": "factory",
    "python-dotenv": "dotenv",
    "psycopg": "psycopg",
    "Pillow": "PIL",
    "PyJWT": "jwt",
    "python-dateutil": "dateutil",
}


def requirements() -> list[tuple[str, str]]:
    """(requirement line, module to import) for everything pinned."""
    wanted = []

    for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue

        # "psycopg[binary]==3.2.3" -> name "psycopg"
        name = line.split("==")[0].split("[")[0].split(">")[0].split("<")[0].strip()
        # Lowercased: the distribution is "Django", the module is "django",
        # and find_spec is case-sensitive where the filesystem may not be.
        module = IMPORT_NAMES.get(name, name.replace("-", "_").lower())
        wanted.append((line, module))

    return wanted


def main() -> int:
    if not REQUIREMENTS.is_file():
        sys.exit(f"No {REQUIREMENTS}")

    missing = [line for line, module in requirements() if importlib.util.find_spec(module) is None]

    print(f"python   : {sys.executable}")
    print(f"missing  : {len(missing)}")

    if not missing:
        print("\nNothing to do - every requirement is importable.")
        return 0

    for line in missing:
        print(f"  - {line}")

    # One pip call, so a kill costs one package rather than the batch. The
    # cache is left on purpose: these wheels have been downloaded several
    # times already by runs that died during install.
    failed = []
    for line in missing:
        print(f"\n--- installing {line} ---", flush=True)
        finished = subprocess.run(
            [sys.executable, "-m", "pip", "install", "--disable-pip-version-check", line],
            capture_output=True,
            text=True,
        )
        print(finished.stdout[-1500:])

        if finished.returncode != 0:
            failed.append(line)
            print(finished.stderr[-1500:])

    print("\n" + "=" * 50)
    if failed:
        print(f"STILL MISSING ({len(failed)}): {', '.join(failed)}")
        print("Run this script again - it continues from here.")
        return 1

    print("All requirements are installed. Restart the app.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
