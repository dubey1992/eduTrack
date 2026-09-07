# eduTrack

A multi-nation School Management System: Laravel REST API + MySQL backend, Flutter (Android + Web) frontend.

Development follows the phase-by-phase process defined in [CLAUDE.md](CLAUDE.md) — read that first. It is
the governing spec for this repo: scope, architecture rules, the multi-nation currency model, and the
full phase plan (Phase 0 → Phase 22).

## Repository layout

```
backend/            Laravel API (PHP 8.3+, MySQL, Sanctum, /api/v1/*)
frontend/            Flutter app (Android + Web, Riverpod, Dio, go_router)
docs/prototype/       HTML UI/product reference the Flutter app follows
scripts/              Local dev helper scripts
CLAUDE.md            Master development spec — read this first
```

## Local setup

### Backend (`backend/`)

1. MySQL must be running locally. On this machine it isn't a registered Windows service (no admin
   rights when it was set up), so start it manually:
   ```
   powershell -File scripts\start-mysql.ps1
   ```
   It listens on `127.0.0.1:3307` (not the standard 3306 — see the note in `backend/.env`). On a normal
   machine with MySQL properly installed as a service, this would just be the default 3306; adjust
   `DB_PORT` in `backend/.env` accordingly.
2. `composer install` (already run for the initial setup)
3. Copy `.env.example` to `.env` and fill in real values if setting up fresh (an `.env` already exists
   for this machine's local dev database — see the credentials handed off separately, not committed).
4. `php artisan migrate`
5. `php artisan db:seed` (creates `test@example.com` / `password` for local testing)
6. `php artisan serve` — API available at `http://localhost:8000/api/v1/`

Run backend tests: `php artisan test` (uses the dedicated `edutrack_testing` database via
`.env.testing`, never the dev database). Check formatting: `vendor/bin/pint`.

### Frontend (`frontend/`)

1. `flutter pub get`
2. `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api/v1` for web, or
   `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1` for the Android emulator
   (emulators can't reach `localhost` directly).

Run tests: `flutter test`. Check formatting/analysis: `dart format lib test` and `flutter analyze`.

## Status

Phase 0 (Foundation) complete: Laravel + Flutter skeletons wired together, working login and
authenticated `GET /api/v1/me`, both with passing automated tests. See [CLAUDE.md](CLAUDE.md) for the
full phase plan — work proceeds one phase at a time.
