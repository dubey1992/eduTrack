"""The entry point cPanel's Python app looks for (docs/deployment.md).

cPanel's "Setup Python App" runs the application under Phusion Passenger, and
Passenger loads exactly this file from the application root and expects a
module-level `application`. Django's own `config/wsgi.py` is that application;
this is the two lines of plumbing that let Passenger find it.

**Nothing is configured here.** The settings module reads the one `.env` that
Laravel also reads, so the web app, `manage.py` and the cron jobs are all
configured the same way and there is no second place to keep in step. If this
file grew a credential, the cron jobs would not have it.
"""

import os
import sys
from pathlib import Path

# Passenger's working directory is not this directory, and the app is imported
# rather than run, so neither the script path nor the CWD puts `config` on the
# path. Prepended rather than appended: a stray `config` elsewhere on the path
# would otherwise win.
HERE = Path(__file__).resolve().parent

if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from config.wsgi import application  # noqa: E402  (the path has to be set first)

__all__ = ["application"]
