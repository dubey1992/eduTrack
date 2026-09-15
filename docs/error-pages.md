# Error and maintenance pages

Four surfaces can tell somebody that things are not normal, and they should
all look like the same product saying it.

| Surface | Who sees it | Where it lives |
|---|---|---|
| A route the app does not have | Somebody already in the app | `frontend/lib/features/errors/presentation/not_found_screen.dart` |
| A path the web host does not have | A stale link, a mistyped URL | `frontend/web/404.html` |
| A bad path on the API host, in a browser | Rare - usually a crawler | `backend/resources/views/errors/404.blade.php` |
| The platform is down on purpose | Everybody | `backend/resources/views/errors/503.blade.php` and the app's `MaintenanceScreen` |

The look is defined twice on purpose - once in Blade
(`backend/resources/views/errors/layout.blade.php`) and once in Flutter
(`frontend/lib/core/widgets/status_page.dart`) - because one of them has to
render when the other's runtime is unavailable. **Change one, change the
other.** Same lockup, same badge, same wording.

Every one of them is self-contained: no stylesheet, font or script fetched
from anywhere else. A maintenance page that needs a CDN is a page that fails
exactly when it is needed, and a test asserts this
(`ErrorPagesTest::test_an_error_page_needs_nothing_from_the_internet_to_render`).

## 404 inside the app

go_router's `errorBuilder` renders `NotFoundScreen` for anything that matches
no route. Where it offers to send somebody depends on whether they are signed
in - "Back to dashboard" for a session, "Go to School365ai" and "Sign in"
without one. Offering the dashboard to somebody with no session just produces
a second dead end.

One subtlety worth knowing about. The router's redirect used to send every
unknown path to `/login` when signed out, which would have swallowed the 404.
It now checks `appRoutePaths` first: an address that is not a route at all is
a 404, not a locked door - bouncing it to the sign-in screen tells somebody
who mistyped a path that they need an account, which is both wrong and
confusing.

`appRoutePaths` is a hand-written set, so it could drift from the routes
themselves. It cannot drift silently: `app_router_test.dart` walks the
router's own configuration and fails if the two disagree in either direction.
Add a route, add it there.

## Scheduled maintenance

Taking the platform down:

```bash
# Optional, but much kinder - shown on the page as "We expect to be back by ..."
# Any format Carbon reads; displayed in PLATFORM_TIMEZONE and US date order.
MAINTENANCE_UNTIL="2026-09-15 18:00"

php artisan down
# ... do the work ...
php artisan up
```

Leave `MAINTENANCE_UNTIL` unset and the page says "back shortly" instead. A
value whose time has already passed is ignored rather than displayed - a stale
one left over from the last window would otherwise promise a return time in
the past, which reads as broken rather than as running late. It is read from
the environment, not from a table, because during maintenance the database is
the thing most likely to be unavailable.

### What the app does

`artisan down` makes the API answer every request with 503. That gets its own
error code rather than a generic one:

```json
{ "code": "SERVICE_UNAVAILABLE", "message": "School365ai is briefly offline for scheduled maintenance. …" }
```

The client needs to tell that apart from anything else, because a maintenance
window is not one screen failing - it is every screen at once. So:

1. The Dio interceptor sets `maintenanceProvider` the moment any response
   comes back 503.
2. The router reads it and holds the whole app on `/maintenance`, ahead of
   every other rule including the session (which cannot be restored while the
   API is down anyway).
3. **Try again** asks the API whether it is back. Any answer that is not
   another 503 means it is - a 401 is the server telling us to sign in, which
   it can only do while running. No answer at all is a network problem, not
   proof the window ended, so that keeps them waiting.
4. When it clears, they go back to their dashboard, or to the homepage if
   they had no session.

## Serving the static 404

`frontend/web/404.html` is copied into `build/web` by `flutter build web`.
On cPanel, point Apache at it in `.htaccess`:

```apache
ErrorDocument 404 /404.html
```

Note that a Flutter SPA is usually served with a rewrite that sends unknown
paths to `index.html`. If that rewrite is in place, the app's own
`NotFoundScreen` handles unknown routes and this file only ever serves paths
excluded from the rewrite (missing assets, for instance). Both are worth
having: the rewrite can be removed or misconfigured, and this file is what
stands between a visitor and the host's default grey 404.
