"""Entry point for the contract suite.

    python contract/run.py

Exists so the suite can be run from the repository root without fighting
Python's import path, and so the failure when the backend is unreachable says
so plainly instead of arriving as an import error.
"""

from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from client import base_url  # noqa: E402


def main() -> int:
    print(f"Contract suite against: {base_url()}\n")

    suite = unittest.defaultTestLoader.discover(HERE, pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)

    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
