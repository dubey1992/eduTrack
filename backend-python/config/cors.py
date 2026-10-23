"""Which origins the browser may call the API from.

One `.env` configures both stacks, so Laravel's `CORS_ALLOWED_ORIGINS` and
Django's own `DJANGO_CORS_ORIGINS` have to agree - and on the first live
deployment they did not, because only the Laravel key was set and Django
quietly kept its development default. The portal's first sign-in was
CORS-blocked by a file that looked configured.

So Django reads its own key first, and otherwise Laravel's - unless that is
Laravel's `*`, which django-cors-headers refuses as an origin and which a
live server must never mean anyway. Then, and only then, the development
default.
"""

DEVELOPMENT = "http://127.0.0.1:5000,http://localhost:5000"


def allowed_origins(environ) -> list[str]:
    for key in ("DJANGO_CORS_ORIGINS", "CORS_ALLOWED_ORIGINS"):
        raw = (environ.get(key) or "").strip()
        if raw and raw != "*":
            return [origin.strip() for origin in raw.split(",") if origin.strip()]

    return DEVELOPMENT.split(",")
