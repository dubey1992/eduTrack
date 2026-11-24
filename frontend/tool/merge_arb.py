"""Builds lib/l10n/app_<lang>.arb from the fragments in lib/l10n/parts and
regenerates the Dart (docs/mobile-apps-review.md, M11).

Each area of the phone apps keeps its strings in its own fragment -
parts/bus_en.json, parts/bus_hi.json, parts/staff_en.json ... - so work on
one app never edits another's lines. Run from frontend/:

    python tool/merge_arb.py

Refuses, and says why, when a key appears in two fragments, or a Hindi
fragment has a key its English one lacks. A lock file keeps two runs at
once from writing over each other.
"""
import glob
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
L10N = os.path.join(HERE, "..", "lib", "l10n")
LOCK = os.path.join(L10N, ".merge.lock")


def load(lang):
    merged, origin = {}, {}
    for path in sorted(glob.glob(os.path.join(L10N, "parts", f"*_{lang}.json"))):
        part = json.load(open(path, encoding="utf-8"))
        for key, value in part.items():
            if key in merged and not key.startswith("@"):
                sys.exit(f"{key} is in both {origin[key]} and {os.path.basename(path)}")
            merged[key] = value
            origin[key] = os.path.basename(path)
    return merged


def main():
    for _ in range(120):
        try:
            fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            break
        except FileExistsError:
            time.sleep(1)
    else:
        sys.exit("another merge has held the lock for two minutes - remove lib/l10n/.merge.lock if it is stale")
    try:
        english = load("en")
        hindi = load("hi")
        extra = sorted(k for k in hindi if not k.startswith("@") and k not in english)
        if extra:
            sys.exit(f"Hindi keys with no English: {extra}")
        for lang, strings in (("en", english), ("hi", hindi)):
            with open(os.path.join(L10N, f"app_{lang}.arb"), "w", encoding="utf-8") as out:
                json.dump({"@@locale": lang, **strings}, out, ensure_ascii=False, indent=2)
                out.write("\n")
        missing = [k for k in english if not k.startswith("@") and k not in hindi]
        result = subprocess.run("flutter gen-l10n", shell=True, cwd=os.path.join(HERE, ".."), capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(result.stdout + result.stderr)
        print(f"{len([k for k in english if not k.startswith('@')])} strings; {len(missing)} not yet in Hindi")
    finally:
        os.close(fd)
        os.remove(LOCK)


if __name__ == "__main__":
    main()
