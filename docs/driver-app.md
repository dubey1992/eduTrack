# The Driver app (Android) — plan for review

*Written 2026-10-22, revised the same day with the three decisions below
answered. Nothing here is built yet; one question is still open.*

**Decided.** A driver and an attendant are **the same thing to this app**:
both sign in, both mark children, and the role they hold is identical. One
codebase, one app. So there is no "driver app" and "attendant app" — there
is **the app the person on the bus uses**, and a driver is now one of the
people who uses it. That makes this plan smaller than the first draft:
there is no second permission set, no second rule about who may mark, and
no second thing on Play.

## The short version

**About two thirds of this app already exists.** The Bus Attendant work
(docs/maps.md, "The Bus Attendant") built a phone-first trip screen, a
mobile-number sign-in that does not depend on a password, an offline queue
for marks made with no signal, position sharing, and Call Parent. A driver
needs nearly the same screen.

What does *not* exist is the part nobody demos: **the app has never been
shipped as an Android app.** It builds, but it is signed with the debug
key, has no Maps key on Android, is named `edutrack_app` with the stock
Flutter icon, and its position sharing stops the moment the phone's screen
goes off. A bus driver's phone is in a cradle with the screen off for most
of a run, so that last one is not a detail — it is the feature.

So the work splits roughly:

| | |
|---|---|
| Reuse as-is | trip screen, offline marks, sign-in, Call Parent, audit, the whole permission set |
| Extend | giving a driver a login, two people marking one trip, today's duty |
| Genuinely new | background position, navigation hand-off, SOS, Android release |

## What exists today, precisely

- **`BUS_ATTENDANT`** — a role for the person on the bus, signing in with a
  mobile number and a 4-digit passcode **on a registered device** (one-time
  setup code, device secret, five wrong tries locks it, an admin can revoke
  a lost phone). Credentials hang off a **staff profile**.
- **My Trip** (`frontend/lib/features/my_trip/`) — today's trips for the
  routes you are assigned, start trip, reach stop, mark each child boarded
  / dropped / absent, end trip, share location, Call Parent.
- **Offline marks** — every mark is saved on the phone first with its own
  id and the time it happened, queued, and resent oldest-first; a resend is
  harmless; marks for an ended trip are refused and listed under "Not sent".
- **Position sharing** — `POST transport/trips/{trip}/locations`, a point
  every 15s, batched, kept 30 days.
- **The trip already names its driver.** `transport_trips.driver_id` is
  required, and `transport_routes.driver_id` assigns one driver per route.
- **Drivers are records, not people who log in**: name, mobile, licence
  number, expiry. There is no `user_id` on `drivers`.

### The Android project as it stands

| Thing | State | Needed for release |
|---|---|---|
| `applicationId` | `com.edutrack.edutrack_app` | the real one, and it can never change after the first upload |
| Signing | **debug key** | upload key + Play App Signing |
| App label / icon | `edutrack_app`, stock Flutter icon | real name and icon |
| Maps API key | **absent from the manifest** | an Android-restricted key (package + SHA-1); the web key will not work |
| Location | `ACCESS_FINE_LOCATION`, explicitly foreground only | a foreground service (below) |
| Push | none (no FCM) | only if we want trip-assigned / SOS-acknowledged alerts |
| Min SDK | Flutter's default | pin it deliberately; bus drivers carry cheap, old phones |

### What the first Android build actually hit *(2026-10-22)*

It did not build at all. Three things in a row, worth writing down because
the next person meets them in the same order:

1. **`flutter_secure_storage` 11 compiles against SDK 37**; Flutter still
   defaults to 36, so the app was refused by the AAR metadata check.
2. **The SDK manager has no `platforms;android-37`.** It publishes the same
   platform as **`android-37.0`** under its new naming, and Gradle looks for
   a directory called `android-37`. So compiling against 37 failed to find a
   platform that is, in fact, installed.
3. **AGP 9.1.0 recommends at most compileSdk 36** and stops the build rather
   than warning.

What makes it build today: `compileSdk = 37` pinned in
`android/app/build.gradle.kts`, `android.suppressUnsupportedCompileSdk=37`
in `android/gradle.properties`, and — **outside the repo** — a junction so
the platform resolves:

```
mklink /J "%LOCALAPPDATA%\Android\Sdk\platforms\android-37" ^
          "%LOCALAPPDATA%\Android\Sdk\platforms\android-37.0"
```

`flutter build apk --debug` then succeeds (173 MB debug APK).

**That junction is the weak part**: any other machine, and CI, needs the
same line or the build fails there while working here. Two ways to be rid
of it, neither urgent: upgrade AGP once a version supports 37, or hold
`flutter_secure_storage` at 10.x, which compiles against 36 — a downgrade
of the thing that stores auth tokens, so not something to do casually.

## The design

**One screen, in a cradle, in sunlight, one-handed, often with no signal.**
That sentence decides most of it.

- **Portrait only, screen kept awake while a trip runs.** A driver should
  never have to unlock the phone to mark a stop.
- **Three states, nothing else**: *Nothing today* → *Today's duty* →
  *Running trip*. No sidebar, no tabs, no search. The web app's navigation
  does not come along.
- **Targets no smaller than 56dp**, high contrast, large type, and the
  primary action always in the bottom third where a thumb reaches.
- **No dialog can appear while the bus is moving** except the two that
  matter: *End trip* and *SOS*. Everything else is a tap with an undo.
- **Offline is the normal case, not an error.** A quiet badge counts what
  is waiting, exactly as the attendant screen does now; a red banner only
  when something was refused and a person must read it.
- **Android back never ends a trip.** Back on the running screen asks
  nothing and does nothing; ending is a deliberate button.
- **Battery.** 15s is right while moving and wasteful at a stop; propose
  distance-filtered updates (send on 50m moved, and at least once a minute)
  so a two-hour run costs a few hundred points rather than five hundred.

### The screens

1. **Sign in** — mobile number, 4-digit passcode, numeric keypad. First run
   takes the one-time setup code from the school and registers the phone.
2. **Today's duty** — one card per trip (pickup / drop): route name, vehicle
   number, start time, how many children, and one big *Start trip* button.
   Below it: today's stop list with times, and the licence-expiry warning if
   it is within 30 days (the driver is the person who should see that first).
3. **Running trip** — the next stop with its distance and ETA, *Reached this
   stop*, the riders for that stop with boarded / absent, *Navigate*, *End
   trip*, and the sync badge. A child already marked shows **who marked them
   and when**, because on a bus with two crew either of them may have done
   it and neither should have to ask.
4. **Trip finished** — what was recorded, what is still queued, and nothing
   that can be edited.

Everything else a driver might want (payslips, leave, profile) stays in the
web app. A driver app that grows a payroll screen stops being usable in a
cradle.

## The functionality, by what it costs

### Reuse without change
Sign-in and device registration · the offline mark queue and its refusal
rules · Call Parent and its audit row · trip start/end and the guardian
alerts they trigger · the live map the office already watches.

### Extend
- **Giving a driver a login** (the open question below). Everything after
  that — the role, the policies, the matrix column — is already there and is
  used unchanged.
- **Two people marking one trip.** This is the one thing the decisions added
  rather than removed, and it is worth getting right.
  - The offline queue's unique mark ids already make a *resend* harmless.
    They do nothing about two **different** phones marking the same child,
    which is now an ordinary event rather than a mistake.
  - **First mark wins, and the second is told so** rather than refused in
    silence: the server answers `already_marked`, with who recorded it and
    when, and the phone shows that instead of the button. A child cannot be
    boarded twice and nobody has to shout down the aisle.
  - **A correction is still possible**, because the first mark can be wrong:
    changing boarded → absent is a new event that supersedes, and both stay
    in the trail. Only the superseding is new; the events table already
    keeps everything.
  - **The phones converge** on the `sync` reply. Each sync already answers
    per mark; it returns the trip's current marks alongside, so the other
    crew member's phone catches up at its next send without a new endpoint
    and without polling.
- **Today's duty screen** — `GET transport/my-routes` already returns the
  routes and today's trips; it needs the vehicle, the stop times and the
  rider count attached, and to answer for a driver as well as an attendant.

### New
- **Position while the screen is off.** The current sharing is a Dart timer,
  which Android suspends with the app. Replace it, on Android, with a
  **foreground service** (`foregroundServiceType="location"`, a persistent
  notification saying the trip is sharing its position) started while the
  app is open and stopped when the trip ends. Done this way it needs
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` and
  `POST_NOTIFICATIONS` — **and not `ACCESS_BACKGROUND_LOCATION`**, which
  would drag in Play's background-location review (a declaration form, a
  demo video, and a published privacy policy). Worth saying plainly: that
  review is weeks of calendar time, so the foreground service is both the
  better engineering and the shorter road.
- **Navigate to the next stop** — hand off to Google Maps with a
  `google.navigation:` intent. In-app turn-by-turn needs the Navigation SDK,
  which is separately licensed and priced; the hand-off is free and is what
  drivers already know.
- **SOS / breakdown** — one button, held for two seconds, that records an
  event on the trip and alerts the school through the existing
  `NotificationService`. The office sees it on the live map.
- **The Android release itself** — the table above, plus a Play listing,
  a privacy policy that actually exists (the footer links at one today),
  and an internal-testing track before anything goes wider.

## Backend changes

Small, which is the point.

- `drivers.staff_profile_id` (nullable FK), by Laravel migration — the one
  schema change in the whole plan.
- `GET transport/my-routes` answers for a driver too: you reach a route if
  you are its attendant **or** its driver's staff member. Vehicle and stop
  times attached.
- `POST transport/trips/{trip}/sync` answers `already_marked` with who and
  when, and returns the trip's marks so the other phone converges. The
  refusal reasons it already has (too old, clock ahead, trip ended, not your
  route) are untouched.
- `transport_trip_events` gains an `sos` type, or a sibling table if we want
  more than a note. Prefer the event type: the live map already reads them.
- Policies: **no new rule, one widened one.** A driver holds the same role
  as an attendant and is limited to the routes they are assigned; the only
  change is that "assigned" now also means being the route's driver.

No change to the trip, mark, or location endpoints beyond that one reply.
That is deliberate: the driver is a second caller of an API the attendant
already proved.

## The phases, and the slices in each

Six phases. Each slice is one commit's worth of work with its own tests,
in the order they have to happen. A slice is done when its tests pass and,
where it has a screen, somebody has seen it on a real phone.

**The order is not negotiable in two places**: D1 before anything else,
because until a signed build installs on a phone every estimate after it is
a guess; and D2 before D3, because two people marking one trip is a rule
the server has to hold before a second person is given a login to break it.

---

### Phase D1 — The app exists on Android

*Nothing below can be checked without this. Two slices need something only
you can give: the Maps key and the keystore.*

**D1.1 — Identity and packaging** *(done 2026-10-22)*
- `applicationId` → `com.school365ai.app` (permanent after the first Play
  upload; the namespace moves with it).
- App name **School365ai Driver App**, with a short launcher label — Android
  shows about 11 characters under an icon, so the full name belongs on the
  Play listing and something like "S365 Driver" under the icon.
- Launcher icon from a real asset, every density, plus the adaptive-icon
  foreground/background.
- `minSdk` pinned deliberately (propose 24 — covers the cheap phones drivers
  carry without dragging in support shims), `targetSdk` at Play's current
  floor.
- `versionCode` / `versionName` from pubspec, as now.
- *Done when:* `flutter build apk --release` produces an APK whose name and
  icon are right on a phone's home screen.

*What it came to.* `com.school365ai.app`, label **School365ai Driver App**,
`minSdk 24`, `targetSdk 36`, and an adaptive icon drawn from the app's own
brand tile — the `#2563EB` square and white mortarboard from
`core/widgets/status_page.dart`, so the launcher and the app agree. Built,
installed on an emulator, and looked at. Two things that only showed up
there:

- **The label truncates to "School365ai…"** under the icon, so the words
  "Driver App" never appear on a home screen. They are right everywhere
  else — Settings, Play, the app list in full. A shorter launcher label is
  one line in `strings.xml` if that matters.
- **Android 12 ignores `windowBackground` for the splash.** It has its own,
  taking its colour from `windowSplashScreenBackground`, so dark mode
  flashed the system's `#121212` before the app's `#0B0F1A` — the exact
  flash the launch theme exists to prevent. Fixed with `values-v31` and
  `values-night-v31`; measured afterwards as `#FFFFFF` light and `#0B0F1A`
  dark, which are `AppTheme`'s own two backgrounds.

**The theme carries over from the web app**, as asked: the Android window
and splash read their colour from the same two values `AppTheme` paints
with, rather than from Android's defaults, so a cold start never shows a
colour the app does not use.

**Not locked to portrait.** It was, for a moment, and that was wrong: one
app serves the admin on a tablet as well as the driver in a cradle, and a
manifest lock applies to everybody. Orientation belongs on the trip screen,
in Flutter, when that screen is built.

**D1.2 — Signing**
- Generate an upload keystore; `key.properties` gitignored and never
  committed, the keystore kept by you.
- Release build type uses it instead of the debug key.
- A written note of where the keystore lives and what losing it costs:
  the app can never be updated again under that listing.
- *Done when:* a release APK installs on a phone and reports the right
  signing certificate.

**D1.3 — Maps on Android** *(needs your key)*
- `com.google.android.geo.API_KEY` meta-data in the manifest, read from
  `local.properties`/Gradle so no key enters the repo.
- Key restricted to the package name + the upload certificate's SHA-1.
- The existing "no key configured" degradation already covers a missing key;
  confirm it on device rather than assume it.
- *Done when:* a route's map draws on a phone, and still degrades cleanly
  with the key removed.

**D1.5 — Only the crew's screens** *(done 2026-10-22; should have been first)*
- `lib/main_driver.dart` and `core/routing/driver_router.dart`: the Android
  build's own entry point, carrying **four screens** — the crew sign-in,
  the trip, the splash, and the maintenance wait — plus one for somebody
  signed in who is not crew, which says so rather than showing them a blank
  screen.
- `CrewFrame` replaces `AppShell` on the phone: who is signed in, and the
  way out. Not a sidebar of twenty modules. The sign-out confirmation is
  the shared one, so it still counts the marks waiting on the phone before
  throwing them away.
- The crew sign-in loses its "sign in with email instead" link in this
  build, because there is no email sign-in here for it to reach.
- Built with `flutter build apk --target lib/main_driver.dart`. **Without
  the `--target` the APK is the web app**, which is exactly the bug this
  slice fixed, so D1.4's CI job has to pass it.
- *Done when:* the installed app opens on "Register this phone" and there
  is no way to reach a school screen from it. Seen on a device.

**D1.6 — An opening, and a screen that says what the app is** *(done 2026-10-22)*
- **The splash** carries a drawn animation — a shuttle running its route,
  children waiting at a stop, the stop emptying as they board
  (`assets/driver/shuttle-run.gif`, generated rather than licensed, 187 KB,
  the app's own palette). Under it, what the app is doing in words, and
  **after six seconds a Try again button**: a phone in a yard on a bad
  network cannot tell a slow morning from a broken app, and a spinner that
  never stops is the worst thing to show somebody about to drive.
- **The opening is held for 1.6 seconds** (`openingBeat`). Restoring a
  session off the phone takes milliseconds, so the first build skipped the
  splash in a single frame and went from the Android launch icon straight
  to the landing — the animation was never seen by anybody. A test now
  fails if that beat goes away. **It costs every launch 1.6 seconds**,
  which is a product choice, not a technical one; say if you would rather
  have the time back.
- **The landing** is the signed-out home: what the app is for, the four
  things it does, and the one thing the crew must fetch before they can
  start — the 8-digit code from the office, good for 24 hours. Written for
  the person on the bus, not the office: short lines and no product words.
  Its button reads **Set up this phone** on a phone nobody has registered
  and **Sign in** on one that has, because a driver who signs out at the
  end of a shift should not be made to read an introduction every morning.
- Sign-in stays reachable from the landing and stays reachable afterwards,
  so reading it once is enough.

**D1.4 — A build that works on more than this machine**
- Decide the `android-37` problem: bump AGP when one supports 37, or hold
  `flutter_secure_storage` at 10.x. Until then, the junction is written down
  in this doc and nowhere else, which is not good enough.
- Add the Android build to CI so it fails there rather than on a release day.
- *Done when:* a clean checkout builds the APK on CI without a manual step.

---

### Phase D2 — Two crew on one trip *(done 2026-10-22)*

*Server-side first, and before any driver has a login. The rules have to
hold whoever is holding the phone.*

**D2.1 — First mark wins**
- `POST trips/{trip}/sync` answers `already_marked` for a child another
  crew member has already marked, carrying who recorded it and when.
- Not an error: the phone shows the line instead of the button.
- Tests: two devices, same child; the second is told, nothing is recorded
  twice, the existing refusals (too old, clock ahead, trip ended, not your
  route) are untouched.

**D2.2 — A correction supersedes**
- boarded → absent (and back) records a new event that supersedes, both
  kept in the trail.
- Tests: the rider's current state, the trail's completeness, and that a
  correction after the trip ended is still refused.

**D2.3 — The phones converge**
- The `sync` reply carries the trip's current marks, so the other crew
  member's phone catches up on its next send. No new endpoint, no polling.
- Tests: a phone that marked nothing learns what the other one did.

**D2.4 — The screen says who**
- Each rider row reads "Boarded by Asha Admin, 9:34 PM" under the child's
  name, where somebody has marked them.

*What it came to.* Most of D2 was already there: the sync reply has always
carried the whole trip back, and the rider state machine already refused a
mark that would undo another. Three things were not:

- **A child already in the state being asked for was recorded again.** The
  state machine only guards *transitions*, so two crew both tapping Boarded
  wrote a second event for a state the child was already in. That is now
  `already_marked`, carrying who got there first and when, and nothing is
  written. The guardian alert was never sent twice - the old test that
  pinned that still passes - but the log gained a row that said nothing.
- **The phone had no word for it.** `MarkResultStatus.fromApiValue` threw on
  anything it did not recognise, so an older app meeting a newer server
  would have crashed on the bus rather than shown a mark as unsent. It now
  falls back to rejected, and `already_marked` is settled, not "Not sent".
- **The rider row never said who.** It does now, from the trip's own events,
  with no new column.

Two things worth knowing about how it was checked. The line sits **under the
child's name**, not beside the status: put beside it, between the badge and
the call button, it had no width left and rendered as nothing on a real
phone while passing its widget test. And the `already_marked` answer cannot
be reached from one phone at all - the button is not offered for a state the
child is already in - so it is covered by the API tests rather than by
tapping.

---

### Phase D3 — A driver signs in

**D3.1 — The link** *(the one schema change)*
- Laravel migration: `drivers.staff_profile_id`, nullable FK.
- Django model, `check_models`, `schema:diff` clean on both databases.
- Tests: a driver with no staff member still works everywhere it did.

**D3.2 — Linking a driver to a staff member**
- Transport → Drivers: pick the staff member this driver is, or leave it
  empty.
- The existing attendant flow then issues the setup code against that staff
  profile — no new auth code.
- Tests: ALLOW/DENY per role, another school's staff cannot be linked,
  audit row on the link.

**D3.3 — The route reaches its driver**
- Policy: assigned means attendant **or** the route's driver's staff member.
- Tests, the important ones: a driver reaches their own route's trips and
  **not** another route's; an unlinked driver reaches nothing.

**D3.4 — Today's duty**
- `GET transport/my-routes` answers for a driver, with vehicle, stop times
  and rider counts.
- The duty screen: today's trips, one Start button, the stop list, and the
  licence-expiry warning when it is within 30 days.
- Widget tests: nothing today, one trip, both trips, a trip already running.

---

### Phase D4 — Position while the screen is off

*The riskiest phase, and the one that decides whether the live map is worth
looking at.*

**D4.1 — The foreground service**
- Android foreground service, `foregroundServiceType="location"`, started
  while the app is open and stopped when the trip ends.
- Permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`,
  `POST_NOTIFICATIONS`. **Not** `ACCESS_BACKGROUND_LOCATION`, which would
  pull in Play's background-location review.
- A persistent notification that says the trip is sharing its position, and
  taps back into the trip.
- *Done when:* a trip keeps reporting with the screen off and the phone in a
  pocket, verified on a real device, not an emulator.

**D4.2 — The battery profile**
- Distance-filtered updates (send on ~50m moved, and at least once a
  minute) in place of a 15s timer, still batched.
- *Done when:* a two-hour run costs a few hundred points rather than five
  hundred, measured.

**D4.3 — Stale is said, not implied**
- The office's live map says "last seen 14 minutes ago" rather than showing
  a stale bus as current.
- Tests: fresh, stale, and never-reported.

**D4.4 — The phones drivers actually carry**
- A help screen for the OEM battery managers that kill foreground services
  (Xiaomi, Oppo, Vivo), and a check on first run.
- *Done when:* a trip survives a run on one of those phones.

---

### Phase D5 — On the road

**D5.1 — Navigate to the next stop**
- Hand off to Google Maps with a `google.navigation:` intent. No Navigation
  SDK, no licence, and it is the app drivers already know.
- Tests: the intent is built from the right stop; a stop with no position
  offers nothing rather than a broken button.

**D5.2 — SOS**
- One button, held two seconds, recording an `sos` trip event and alerting
  the school through the existing `NotificationService`. Visible on the live
  map.
- Tests: the event, the alert, the audit row, and that a stray tap cannot
  send one.

---

### Phase D6 — Release

**D6.1 — A privacy policy that exists**
- Required by Play for a location app, and the footer link currently points
  at a page that does not exist. The two are the same job.

**D6.2 — The Play listing**
- Internal testing track first, data-safety form, location disclosure,
  screenshots, description.

**D6.3 — Real drivers, real phones**
- A week of real trips on the fleet before anything goes wider, with the
  office watching the live map and comparing it to where the bus was.

## Out of scope for this app

Parent tracking (a separate audience and a separate app), fuel and
maintenance logs, speeding or harsh-braking scoring, in-app turn-by-turn,
iOS, attendance for anything but transport, and any screen that exists to be
read at a desk.

## Risks worth naming now

- **Cheap Android phones.** Aggressive battery managers kill foreground
  services on some OEM skins (Xiaomi, Oppo, Vivo are the usual ones). Plan
  on a "keep the app running" help screen and testing on the phones drivers
  actually carry, not a Pixel emulator.
- **The office's live map is only as good as the worst phone on the fleet.**
  If positions stop, the map must say *last seen 14 minutes ago* rather than
  show a stale bus as if it were current. Worth checking what it does today.
- **Play review** rejects location apps with thin disclosure. The privacy
  policy and the in-app explanation are part of the work, not paperwork
  after it.
- **One driver, one route** is what the schema says (`OneToOne`). If a
  driver covers two routes in a morning, that assumption breaks and the
  column has to change. Worth confirming against how schools actually run.

## Decided

1. **A driver signs in, exactly as an attendant does** — mobile number,
   4-digit passcode, registered device.
2. **The role is identical.** One role, one permission set, one column in
   the matrix. Nothing distinguishes a driver from an attendant except the
   job they do on the bus.
3. **Both mark children.** Hence the first-mark-wins rule and the
   who-marked-it line above; this is the only place the decision adds work.
4. **One codebase, two entry points.** `lib/main.dart` is the school's web
   app; `lib/main_driver.dart` is what Android builds. They share the
   theme, the network layer, the auth notifier and the trip screen itself —
   everything but the router.

   *This was first written as "one app, and the role decides what you see",
   which was a misreading, and the build proved it: an app called School365ai
   Driver App opened on the marketing homepage with a Join Early Access
   button on it. Hiding the office behind a role is not the same as not
   shipping it. The driver build does not contain the homepage, the
   sidebar, or a single screen of the school.*
5. **`com.school365ai.app`**, named **School365ai Driver App**. Permanent
   once it is uploaded.
6. **The keystore is yours to keep.** Generated here, kept by you, never in
   the repo.

One wrinkle in the name, worth a sentence rather than an argument: the
attendant installs this too, and will see "Driver App" on their phone.
Either that is fine — drivers are the ones it is bought for — or the
launcher label says something that covers both crew while the Play listing
keeps the full name. A one-line change either way, and better decided now
than after a thousand installs.

## A driver is a member of staff

*Decided.* **A driver is staff, under transport management** — an employee
with a staff profile, like everybody else who works at the school, and the
sign-in credential hangs off that profile exactly as an attendant's does.
No new auth, no new role, nothing new in the permission matrix.

That leaves one thing to join up. `drivers` stays — it is the **licence
record**: licence number, expiry, and what `transport_routes.driver_id` and
`transport_trips.driver_id` point at. Without a link, the same human is two
unconnected rows, and the trip names a record rather than the person who
signed in. So: **`drivers.staff_profile_id`**, one nullable column by
Laravel migration, and the driver row becomes "this staff member's licence
and bus assignment".

Nullable, because a school may well record a driver before that person has
a login, and should not be stopped from doing so. A driver with no staff
profile simply cannot sign in — which is today's behaviour, unchanged.

**The policy follows from it.** Today you reach a route if you are its
`attendant_user`. Now: if you are its attendant **or** its driver's staff
member. One `OR`, in the policy that already exists.

## How the bus is actually crewed

*Told to me, and it shapes the screen more than anything else here:*
**most trips are a driver and one attendant; sometimes the driver runs the
bus alone and marks the children too.**

- The solo case is not an exception to design around — it is the reason a
  driver marks at all, and it means **every control must work with one
  person**: start, reach stop, mark, end. Nothing may require a second pair
  of hands.
- The paired case is the common one, so the first-mark-wins rule and the
  "marked by Anil, 7:42" line are not edge-case polish; they are what two
  people see most mornings.
- A route already names both — `driver_id` and `attendant_user_id` — so
  both crew find the same trip on their own phone with no new assignment
  screen.
- **A trip is never blocked on who marked what.** If the attendant's phone
  is flat, the driver finishes the run alone, and the trail says so.

## One more thing worth a word: the role's name

With drivers inside it, the stored role `BUS_ATTENDANT` reads wrong on a
driver's screen and in the permissions matrix. The cheap fix is to change
only what people read — "Bus Crew", say — and leave the stored value alone:
no migration, no risk, and the word on screen is right. A real rename of the
stored value is possible later and costs a data migration plus every place
the value is written down. Say which you'd prefer; the label is a one-line
change either way.
