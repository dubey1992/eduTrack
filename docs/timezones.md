# Timezones

eduTrack is sold in more than one country, so "today" is not a property of
the server. It belongs to the school.

This note explains the rule, where it is enforced, and what to do when you
add a feature that touches a date.

## The one rule

**An instant is stored in UTC. A calendar date is stored as the date it was
at the school.**

| Kind | Examples | Stored as | Read as |
|---|---|---|---|
| Instant | `created_at`, `sent_at`, `started_at`, `boarded_at`, `published_at` | UTC datetime | rendered into the school's zone for display |
| Calendar date | `attendance_date`, `payment_date`, `trip_date`, `start_date`, `expires_at` | plain date, already school-local | compared against the school's today |

An instant does not belong to a timezone — only its *rendering* does. A
calendar date has no instant at all: a register marked on the 17th was marked
on the 17th, whatever time it was anywhere else.

## Where the zone lives

`schools.timezone` holds an IANA name such as `Asia/Kolkata`. It is required
when a Super Admin creates a school, and editable afterwards from the same
form — a school genuinely can be set up wrong on day one, and unlike
`currency_code` there is no historical snapshot to corrupt, because instants
are stored in UTC and simply re-render.

The field opens a searchable list rather than a plain dropdown: there are
several hundred zones, and "kolkata", "pacific" or "+05:30" all narrow it. The
options are served by `GET /api/v1/timezones`, so the picker can never offer a
zone the backend would reject, and it stays correct as the IANA database
changes.

Existing schools were backfilled to `UTC`, which is exactly what the
application assumed before the column existed.

### `APP_TIMEZONE` is gone

`config('app.timezone')` is now hardcoded to `UTC` and must stay that way.
PHP writes every timestamp column in that zone, so changing it would store
wall-clock readings instead of instants and silently re-interpret every row
already in the database.

The deployment-level setting that remains is `PLATFORM_TIMEZONE`
(`config('app.platform_timezone')`), and it governs only the handful of views
that belong to no school — the Super Admin's cross-school payment totals,
where "this month" cannot mean any one school's month. School-owned data
never uses it.

## The backend

Everything goes through `App\Support\SchoolClock`.

```php
$clock = SchoolClock::for($school);            // a school's clock
$clock = SchoolClock::forUser($actor);         // the clock of the user's school
$clock = SchoolClock::forScope($actor, $id);   // a listing's clock - see below
$clock = SchoolClock::platform();              // cross-school views only

$clock->date();                  // '2026-09-17' at the school
$clock->today();                 // midnight there
$clock->now();                   // the time there
$clock->format($instant, 'g:i A');  // an instant, as the school reads it
[$from, $to] = $clock->todayRange(); // the UTC window covering its day
```

`forScope()` answers "whose day is this listing about": a school user always
means their own school; a Super Admin means whichever school they filtered
to, or the platform when they are looking across all of them.

An unknown or retired zone falls back to UTC rather than throwing, so one bad
row cannot break every request that touches a date.

### Comparing a timestamp to a date

This is the trap. `whereDate('created_at', '2026-09-17')` is wrong, because
`created_at` is UTC and the school's 17th began at 18:30 UTC on the 16th.
Use the window instead:

```php
[$start, $end] = $clock->todayRange();

$query->where('created_at', '>=', $start)->where('created_at', '<', $end);
```

`startOfDayUtc()` and `endOfDayUtc()` do the same for an arbitrary date. The
range is half-open on purpose: `< end` has no sub-second gap the way
`<= 23:59:59` does.

### Validation

Laravel's `before_or_equal:today` resolves "today" from the server. A teacher
in Asia/Kolkata marking the register at 7am is five and a half hours ahead of
that, so before 05:30 UTC the server would reject the date as being in the
future.

Form Requests use `App\Http\Requests\Concerns\ChecksSchoolDates` instead:

```php
use ChecksSchoolDates;

'attendance_date' => ['required', 'date', $this->notInFuture()],
'expires_at' => ['nullable', 'date', $this->notInPast()],
```

### Rendering times in a response

`App\Http\Resources\Concerns\RendersSchoolTime` gives a resource
`timeLabel()`, `dateLabel()` and `dateTimeLabel()`. A parent resource that
has already resolved its clock passes it down with `usingClock()`, which
keeps a trip's forty riders from each looking up their own school.

A resource whose model carries no `school_id` and was given no clock throws
rather than guessing — falling back to the platform zone there would print a
plausible, wrong time.

## The client

Flutter ships no timezone database, and adding one would cost about a
megabyte in the web bundle for something the server already knows. So the
split is:

- **Displaying an instant** — the API sends a rendered label next to it
  (`sent_at_label`, `started_at_label`, `published_at_label`). The client
  never parses the raw UTC value. There is no `toLocal()` anywhere in `lib/`.
- **Deciding a date** — a date picker's default and its bounds, "is this
  today", which weekday it is. These come from `SchoolClock` in
  `lib/core/utils/school_clock.dart`, read through `schoolClockProvider`.

The session payload (`/auth/login` and `/me`) carries `timezone` and
`current_time`, an ISO string with the school's offset. The client stores the
reading and the instant it was taken, then adds elapsed time — so a tab left
open across midnight still rolls over.

There is no `DateTime.now()` in `lib/` outside `SchoolClock` itself.

### Resolve the clock in `build`, not `initState`

A screen may mount while the session is still loading, and reading the clock
then would silently pin it to the device. Keep the user's choice nullable and
fall back to the clock on each build:

```dart
DateTime? _pickedDate;

DateTime get _date => _pickedDate ?? ref.read(schoolClockProvider).today;
```

### Known limit

A daylight-saving change *during* an open session leaves the client's clock
an hour out until the session is refetched. Chasing that would mean shipping
the timezone database to the browser. The server is never wrong about it, so
nothing is stored incorrectly — only a picker's default could be off, and
only within an hour of midnight on the two days a year a zone shifts.

## Adding a feature that touches a date

1. Decide which kind it is — instant or calendar date. Most bugs start here.
2. Never call `now()->toDateString()`, `Carbon::today()` or
   `whereDate(<timestamp column>, ...)`. Use the clock.
3. Validate "not in the future" with `ChecksSchoolDates`, never with
   `today`.
4. If the client shows the time, send a rendered label; do not make Flutter
   parse the instant.
5. Test it at a moment when the server and the school disagree about the
   date. `SchoolTimezoneTest` freezes two:
   `2026-09-16 19:00 UTC` (Asia/Kolkata is on the 17th) and
   `2026-09-16 02:00 UTC` (America/New_York is still on the 15th).
