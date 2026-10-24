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

*Fixed in D1.4 by upgrading.* For a while it built on this machine only,
with `compileSdk = 37` pinned, `android.suppressUnsupportedCompileSdk=37`
and a junction linking `platforms/android-37` to `platforms/android-37.0`.
AGP 9.3.3 and Gradle 9.5.0 removed the need for all three: that AGP reads
the new naming and allows 37. The pin stays, because the plugin still asks
for 37; both workarounds are gone, and a clean build with the junction
deleted proves it.

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

**D1.2 — Signing** *(done 2026-10-23)*
- An upload keystore at **`C:\Users\abhis\keystores\school365ai-upload.jks`**,
  alias `upload`, RSA 2048, valid 10000 days. Deliberately outside the
  repo; `android/key.properties` points at it and holds the password, and
  `android/.gitignore` ignores both that file and any `.jks`.
- The password was generated at creation and written only into
  `key.properties`. It was passed to `keytool` through the environment
  rather than the command line, so it never reached a process list, and it
  has never been printed anywhere.
- **The release certificate's SHA-1 is
  `47:2C:35:3F:C6:C2:7F:23:C0:16:D8:8B:B6:F6:8D:0B:88:A2:80:2D`** — not a
  secret, and what the Google Maps key restriction needs alongside the
  package name.
- **A machine without the keystore still builds.** The release falls back
  to the debug key, so CI and a fresh checkout work; such a build simply
  cannot be uploaded to Play. Checked by moving `key.properties` aside and
  building: the APK came out signed `CN=Android Debug`, and with it back,
  `CN=School365ai`.
- *Done when:* a release APK installs on a phone and reports the right
  signing certificate. **Done** — installed and opened on the emulator.

> **Back up the keystore and `key.properties` somewhere that is not this
> machine.** Losing either one means this app can never be updated under
> its Play listing again — a new key is a new listing, and every installed
> copy stops receiving updates. This is the single most unrecoverable file
> in the project.

**D1.3 — Maps on Android** *(settled 2026-10-23)*
- `com.google.android.geo.API_KEY` meta-data in the manifest, read from
  `local.properties`/Gradle so no key enters the repo. Verified resolved in
  a built APK's merged manifest — checked by length, never printed.
- Key restricted to the package name + the upload certificate's SHA-1.
- *And then the slice turned out to be smaller than it looked:* **no crew
  screen draws a map.** The duty screen is a list, the trip screen is a
  roster, and D5.1 hands navigation to Google Maps by intent rather than
  drawing a route in-app — which is the decision that makes the Navigation
  SDK and its licence unnecessary. So there is no map to confirm on a
  phone; the key is wired for the day one appears, and the portal that does
  draw maps is unaffected.

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
- **The opening is held for one full pass of the animation** —
  `openingBeat`, 2.6s. Restoring a session off the phone takes
  milliseconds, so the first build skipped the splash in a single frame
  and went from the Android launch icon straight to the landing; the
  animation was never seen by anybody. The length is the loop's own: 36
  frames at 70ms is 2.52s, which is the bus arriving, the children
  boarding and the bus pulling away. Held any shorter and the crew sees a
  fragment — a bus that never reaches the stop — which reads as the app
  stuttering rather than as a scene. Two tests hold this: one fails if the
  beat goes away, one if it is cut below a loop. **It costs every launch
  2.6 seconds**, a product choice rather than a technical one.
- **The landing** is the signed-out home: what the app is for, the four
  things it does, and the one thing the crew must fetch before they can
  start — the 8-digit code from the office, good for 24 hours. Written for
  the person on the bus, not the office: short lines and no product words.
  Its button reads **Set up this phone** on a phone nobody has registered
  and **Sign in** on one that has, because a driver who signs out at the
  end of a shift should not be made to read an introduction every morning.
- Sign-in stays reachable from the landing and stays reachable afterwards,
  so reading it once is enough.

**D1.4 — A build that works on more than this machine** *(done 2026-10-23)*
- **The junction is gone, and so is the suppress flag.** AGP 9.3.3 (with
  Gradle 9.5.0, which it requires) understands the SDK manager's new
  naming, so `compileSdk = 37` resolves `platforms/android-37.0` on its
  own and its ceiling now allows 37. Both workarounds were deleted and a
  clean build — `flutter clean`, caches dropped, the junction removed from
  the SDK — came out fine. The third option, holding
  `flutter_secure_storage` at 9.x, was not taken: swapping the thing that
  stores auth tokens to dodge a build-config problem is the wrong trade.
- **CI builds the APK.** A new `android` job: JDK 17, Flutter, then
  `flutter build apk --debug --target lib/main_driver.dart`. Nothing else
  in the workflow compiles a line of Android — the Flutter job runs Dart
  tests, which never touch Gradle, the manifest or the SDK — so without
  this the APK breaks on the day somebody tries to cut a release.
- The `--target` is not optional in that job either: without it CI would
  cheerfully build the school's web app into an APK and call it green.
- *Done when:* a clean checkout builds the APK on CI without a manual step.
  **The local half is proven; the CI half is not yet** — it cannot be,
  until the job has run once on GitHub. Watch the first run.

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

**D3.4 — Today's duty** *(done 2026-10-23)*
- `GET transport/my-routes` answers for a driver, with vehicle, stop times
  and rider counts — shipped with D3.3, since the route reaching its driver
  and the driver seeing it are the same sentence.
- The duty screen: today's trips, one Start button, the stop list.
- **The licence warning, and who may read it.** A driver is told when their
  own licence runs out, from 30 days before, and told plainly once it has.
  The date is sent *only* to the driver it belongs to — an attendant gets
  null, because a colleague's papers are not theirs to read, and the office
  already has them on the Drivers screen.
- It never blocks a trip. A lapsed licence is a conversation with the
  school, not a reason to strand children at a stop; the warning says who
  to tell.
- Tests: nothing today, one trip, both trips, a trip already running, no
  route, no signal — and, new here, expiring / expired / months-away /
  not-my-licence, with ALLOW and DENY on the server.

---

### Phase D4 — Position while the screen is off

*The riskiest phase, and the one that decides whether the live map is worth
looking at.*

**D4.1 — The foreground service** *(built 2026-10-23)*
- Android foreground service, `foregroundServiceType="location"`, started
  while the app is open and stopped when the trip ends.
- Permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`,
  `POST_NOTIFICATIONS`. **Not** `ACCESS_BACKGROUND_LOCATION`, which would
  pull in Play's background-location review — a declaration form, a demo
  video and weeks of calendar time, for a service the app does not need.
- A persistent notification that says the trip is sharing its position, on a
  LOW-importance channel: it has to be there, but it is a statement, not an
  interruption, and a driver does not need a sound every time.
- Shaped so the web build never sees any of it: `TripService` with
  `trip_service_io.dart` / `trip_service_web.dart` behind a conditional
  import, so the portal keeps building and the notifier has one thing to
  call. The notifier holds its service from `build()` rather than reading it
  in `onDispose`, which Riverpod forbids.
- **Two things the plugin does not do for you**, both found by looking at
  `dumpsys` rather than at the app, which showed nothing wrong:
  - The plugin ships the service class but declares it in *no* manifest —
    only the app knows its `foregroundServiceType`, and from Android 14 a
    service started without the right one is refused. Android's answer was
    one line in logcat: *"Unable to start service ... not found"*.
  - From Android 13 the notification needs permission, and the notification
    *is* the foreground service — refuse it and nothing starts. We now ask
    the moment the driver switches sharing on, which is when the reason for
    asking is on the screen behind the prompt.
- *Verified 2026-10-23, screen off:* `isForeground=true`, type `0x8`
  (location), channel `trip_in_progress`; the shade reads "Trip in progress
  - Sharing this bus's position with the school." under Silent. With the
  device asleep the trip posted a position every 15s for 90s, and ending the
  trip took the service and its notification away with it.
- *Still open:* that was an emulator. The phones that kill foreground
  services are Xiaomi, Oppo and Vivo, which is D4.4's whole subject — so the
  real-phone check belongs there rather than being claimed here.

**D4.2 — The battery profile** *(built 2026-10-23)*
- One continuous position stream in place of a fresh high-accuracy fix every
  15 seconds. Android is told both rules — at least 50 m apart, at most one
  every 15 s — so the *platform* decides when the bus has moved and the app
  sleeps in between instead of waking to throw a position away.
- A point is kept when the bus has moved 50 m, which is about a bus length
  and a half: movement, rather than a parked phone's fix wandering.
- A standing bus still reports **once a minute**, from a real fix. The
  tempting cheap version — re-stamp the last position with the time now —
  was not built: the office reads that line as "where the bus is now", and
  D4.3 only works because that sentence is true.
- The heartbeat is a one-shot timer re-armed by every kept point, not a
  periodic one. A moving bus therefore never reaches it, and the rule needs
  no clock arithmetic to express — which is also why it is testable.
- *Measured on an emulator, standing still:* four positions a minute before,
  one after. Over a two-hour run that is 480 points against 120, and a
  moving bus is unchanged at its 15 s ceiling — so the saving is taken
  entirely out of the standing time, which is where it was.

**D4.3 — Stale is said, not implied** *(already built, verified 2026-10-23)*
- The maps work (docs/maps.md, M3) delivered this before the driver app
  existed, so there was nothing to write. The API answers `age_seconds` and
  `is_stale`; the card reads "Last seen 14 minutes ago (stale)" and greys
  itself; the bus pin switches to `MapPinColour.busStale` and its info
  window carries the same sentence.
- Checked rather than assumed, and left alone.

**D4.4 — The phones drivers actually carry** *(built 2026-10-23)*
- Two settings stand between a correct foreground service and a bus that
  stays on the map. The first, Android's own battery optimisation, *can* be
  asked for from code, and the help screen's one button does. The second —
  the layer Xiaomi, Oppo and Vivo add on top — kills services on its own
  schedule, sits somewhere different on every phone, and has **no API at
  all**. That half is a person tapping through Settings, so the screen is
  written as steps by make rather than as a button that cannot exist.
- The warning lives on the **duty screen**, before the run: a driver can
  walk through Settings in the yard at seven, and must not be sent into them
  at the wheel. It shows only when the phone is actually restricted.
- The screen is also always reachable from the crew app bar, because Android
  can report this app as exempt while the manufacturer's own manager kills
  it anyway — and that driver needs the steps too, with no warning to tap.
- Makes covered: Xiaomi/Redmi/POCO, Oppo/Realme/OnePlus, Vivo/iQOO, Samsung,
  and a generic path for anything else.
- *Still open:* "a trip survives a run on one of those phones" — which needs
  one of those phones. This is where D4.1's real-device check belongs too.

---

### Phase D5 — On the road

**D5.1 — Navigate to the next stop** *(done 2026-10-23)*
- Hand off to Google Maps with a `google.navigation:` intent, which starts
  guidance rather than opening a preview. No Navigation SDK, no licence, and
  it is the app drivers already know.
- A phone without Google Maps falls back to an ordinary directions URL, so
  the button is never dead. Android 11+ hides other apps unless they are
  declared, so both schemes are in the manifest's `<queries>`.
- Offered on the next stop only, and only when that stop has been placed on
  the map. A stop nobody has surveyed offers nothing — a button that does
  nothing is worse than no button.
- Tests: the link's exact shape (including a southern/western stop), the
  right stop's position, an unplaced stop, a reached stop, a stop that is
  not next, and a phone with no maps app at all.
- *Verified on the emulator:* tapping it starts Google Maps on
  `act=VIEW dat=google.navigation:`, which is the hand-off working rather
  than a button that merely looks right.

**D5.2 — SOS** *(done 2026-10-23)*
- One button, **held two seconds**, with the hold drawn as it fills. Held
  rather than tapped because of where it lives: a phone in a cradle on a
  moving bus, under a driver's hand, on the same screen as the buttons they
  press forty times a morning.
- It changes nothing about the trip. The bus keeps running, the children
  stay marked, nothing is cancelled — somebody on a road wanted a person,
  not a state machine.
- It rides the **same offline queue** as every other mark, because a road
  with no signal is exactly when an SOS must be kept and sent later. Same
  `client_id`, so a second send alerts nobody twice.
- Goes to the transport managers **and** the admins, not one or the other:
  this is the case where the manager's phone being off must not be the end
  of it. The message carries the crew member's own number, because an alert
  nobody can answer is not an alert.
- **No school can switch it off.** The transport switch is about what
  guardians are told; a crew asking for help is not a setting.
- On the office's trip timeline it is drawn in the danger colour with its
  own icon, so somebody scrolling in a hurry finds it.
- Tests: the event and its audit row, who is told and what the message says,
  that the trip is untouched, that it needs no child or stop, that a repeat
  send alerts once, that a switched-off school still gets it — and, on the
  phone, that a stray tap and an early release both send nothing.
- **What the tests could not see.** On a real phone the first build did
  nothing: the app wrapped every screen in a `SelectionArea` so the office
  can copy a name, and that claims the long press — the label highlighted, a
  Copy bar slid in, and the call for help never left. Two changes, found
  only by holding the button on a device:
  - the driver build **has no SelectionArea at all**. Nobody on a bus copies
    anything, and a feature nobody uses is not worth a gesture they do;
  - the button listens to **raw pointer events** rather than using a gesture
    recogniser, because a recogniser has to win an arena and this one could
    not. It cancels itself if the finger travels, so a thumb resting there
    while the trip sheet scrolls sends nothing.
- `sos_selection_test.dart` wraps the button in the SelectionArea the app
  used to have, so the bug cannot come back quietly. It fails on the old
  code — checked.
- *Verified on the emulator:* three SOS events, twelve alerts across two
  recipients and four channels, two audit rows, the trip still in progress,
  and the message reading "SOS from ITest Route (ITest Bus): Imran Khan
  asked for help at 10/23/2026 11:51 AM on the drop run, with 0 on board."

---

### Phase D7 — Guidance inside the app *(built 2026-10-23, running 2026-10-24)*

*D5.1 handed the stop to Google Maps and said so was enough. Asked to do
the other thing, here is what it actually took.*

**D7.1 — The SDK in the build**
- `google_navigation_flutter` 0.11.2, Google's own plugin. Four separate
  toolchain fights, none of them about navigation:
  - the Navigation SDK **contains** the Maps SDK, so a build with both it
    and `google_maps_flutter` dies in several hundred "Duplicate class
    com.google.android.gms.maps..." errors. The standalone Maps library is
    excluded, and the navigation artifact provides those classes;
  - it needs core-library desugaring, in the `_nio` flavour, because it uses
    `java.nio.file` and this app's floor is Android 7;
  - version 0.6.4 pulled three Cronet artifacts sharing one namespace, which
    AGP 9 rejects outright. 0.11.2 does not;
  - and it is compiled against android-35 while `flutter_plugin_android_lifecycle`
    demands 36 of everything that depends on it. Neither is ours to fix, so
    the compile-time check is switched off in `gradle.properties`. minSdk —
    which decides which phones run the app — is untouched.
- The web portal still builds: everything SDK-shaped is behind the same
  conditional import the foreground service uses.

**D7.2 — The screen, and its way out**
- `/navigate` shows guidance for one stop. Every path through it assumes
  the SDK can refuse, because it can: an unauthorised key, a driver who
  declines Google's terms, no route. Each says so in one sentence and
  offers **Open Google Maps** — the D5.1 hand-off, kept precisely so this
  phase could not strand anybody.
- **Deadlines on every SDK call.** Found on the device: with a key the
  Navigation SDK is not enabled for, the SDK logs "Authorization failure"
  and then never answers. Unbounded, that is a driver holding a spinner
  with a run to start. Ten seconds for each call, thirty for Google's
  consent dialog.

**D7.3 — What it took to switch on** *(done 2026-10-24)*
- Verified first with the key refused: the SDK initialises, reaches Google,
  is turned away, and the app falls back to Google Maps exactly as designed.
- Then with **Navigation SDK** enabled on the Cloud project that owns the
  Android key: Google's consent sheet ("Navigate to your stops… Got It")
  the first time only, then turn-by-turn drawn inside the app — route,
  manoeuvre card, ETA, Google's own 3D map — for Shivajinagar on the Map
  Demo Route, on the emulator parked in Pune. Reproduced from a wiped
  install (terms and registration gone) and from a cold start; both well
  inside the deadlines. Leaving the screen ends guidance.
- What the Cloud side needs, for the record: the Navigation SDK API
  enabled with billing (routes are billed per destination, first 1,000 a
  month free); the Android key restricted to `com.school365ai.app` with
  each signing certificate's SHA-1 - the debug certificate's for test
  builds, the upload keystore's for the release; and Navigation SDK among
  that key's allowed APIs.
- **One thing seen once and not again:** the very first attempt on this
  emulator, minutes after the API was switched on, came back refused and
  the screen said guidance was "not switched on for your school yet" -
  which was by then untrue. Every attempt since, including the wiped-install
  repeat, has worked. The likeliest reading is Google taking a few minutes
  to propagate a freshly enabled API; a driver cannot hit that. If it ever
  shows up on a phone, the words are the bug to fix first: a deadline and
  a refusal are different things and should not share a sentence.

**And a bug this phase found in the last one**
- The driver router sent every address that was not the trip or the profile
  straight back to the trip. **Battery help (D4.4) had therefore never
  opened on a phone**, and nor would Navigate. Both had passing tests — of
  the screens, and of the buttons that open them — because neither went
  through the router. The reachable set is now one list beside the routes,
  and two tests push through the real router to land on each.

---

### Phase D8 — Finding a child on a full bus *(built 2026-10-24)*

*Asked for after a demo of a school with three routes, five stops each and
ten children a stop: fifty cards on the trip sheet, and the one who has
just climbed on somewhere in the middle of them.*

**D8.1 — A search box that stays put**
- Above the list, not in it: it is wanted most when the sheet is longest.
  Type a name, part of one, an admission number or a class; the sheet
  narrows to the children who match, each still under their own stop, and
  a stop with nobody matching is left out rather than left as a heading
  that says where the child is not. Marks work from the narrowed sheet
  exactly as from the full one. Nobody matching says so, with Clear.
- **Forgiving on purpose.** A word matches when it starts one of the
  child's, or when it is a letter or two off - one for words of four or
  five letters, two from six, none below that or "Sai" would find half the
  bus. Every word asked for has to land somewhere, so "Sai Verma" finds
  nobody rather than two children (`rider_search.dart`, with the cases in
  its test).

**D8.2 — Saying the name**
- A microphone button in the same box, for crew who would rather not type.
  It fills the box with what the phone's own recogniser hears, as it
  hears it, and stops at a pause, after eight seconds, or on a tap. Nothing
  else about the screen changes, and nothing of ours is involved - no
  account, key or server; it is the keyboard's microphone key, wired to
  this one field.
- `speech_to_text`, the long-standing plugin over Android's recogniser,
  behind the same kind of interface as navigation and the foreground
  service: the web portal gets none of it, tests hear what they are told
  to, and the web build shows no microphone. The permission is asked for
  the first time the button is tapped - found on the tablet when it was
  asked on opening the trip instead, which is the wrong moment: setting the
  recogniser up is what prompts, so it is set up on the tap. A phone that
  then refuses is told once, in a sentence, and the button stays for the
  next time.
- The forgiving match above is what makes this usable: a recogniser says
  "Kabeer" for Kabir and "Sai Ayer" for Sai Iyer, and the child is found
  anyway.

**D8.3 — Two things checked at the same time**
- *Dropping a child who never boarded.* Already refused on both sides: the
  Dropped button is disabled for a Pending child, and the server answers
  `INVALID_RIDER_STATUS_CHANGE` to the same request made directly (the
  state machine in `TripRiderStatus.can_become`, with its test). Nothing
  to add.
- *A crew member's mobile in Profile.* The server already refused the
  change (it is how they sign in); the app still offered the box and the
  refusal. It now shows the number as a fact, says the school office
  changes it, and never sends it back - a reformatted number would have
  read as a change.

---

### Phase D6 — Release

**D6.1 — A privacy policy that exists** *(drafted 2026-10-23 — needs your review)*
- `/privacy`, public like the homepage: it has to open for a parent, a Play
  reviewer or a school's lawyer, none of whom have an account. The footer's
  Privacy Policy link now points at it instead of at a page that never
  existed.
- Written from what the code actually does, and the tests pin the promises:
  location only while a trip runs, no background-location permission,
  positions deleted after 30 days, a guardian's number never recorded, and
  the third parties that genuinely do receive something — Google Maps,
  Google Fonts (the typeface is fetched at runtime, so Google sees the
  request), the school's own messaging provider, and the hosting.
- **What it deliberately does not say:** who the operating company is, its
  address, or which country's law applies. Those are facts about the
  business, not the software, and inventing them would be worse than leaving
  them out — the page points to the school's agreement instead. Fill those
  in before the Play listing goes anywhere.
- *Needs a look from you, and probably from a lawyer.* This is a legal
  document that happens to have been drafted by reading the source.

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

## The crew's session runs until they sign out

*Decided 2026-10-23.* Everybody else's session lapses - seven days idle,
thirty days absolute (docs/security.md, Phase 21). **The bus crew's does
not.** A teacher at a desk can sign in again in ten seconds; a driver is in
a yard at six in the morning, often with no signal, and a session that
lapsed overnight means a run that starts with nobody able to mark a child.

The second factor is unchanged: the passcode only works on a registered
device, so the phone is the lock whether the session is a day old or a
year. What ends a crew session is a deliberate act - signing out, an admin
revoking the phone, the account being deactivated or locked. All of those
still work, and they work in minutes; an idle timer works in seven days.

Two things this also fixed on the phone, both of which threw a session away
without anybody asking:

- **A server having a bad morning signed the crew out.** Any error with a
  response cleared the token - a 500, a proxy's 502, a maintenance 503.
  Only a 401, the server saying "this is not a session", does now.
- **An offline start with nothing cached cleared the token too**, which is
  the worst possible moment for it: somebody who cannot reach the server
  also cannot sign in again. The token is kept and the next launch asks
  again.

Checked on a phone with the network switched off entirely: the app opens
signed in, shows the routes saved on the phone, and says *"No signal -
showing your routes as last saved on this phone."*

**The trade, stated plainly:** a lost phone stays signed in until somebody
notices and revokes it. That is the right answer for a bus - a timer would
not have shut out a thief inside seven days either - but it makes the
admin's "sign this phone out" the thing that matters, and it should be easy
to find when a crew member reports a lost handset.

## The day closes itself

*Decided 2026-10-23, after a driver met it on an emulator.* A crew member
who forgets to end a trip blocks the next morning's run: the route already
has one in progress, and only the office can clear it. The driver finds
that out in a yard at six, which is the worst moment and the wrong person.

`python manage.py close_open_trips`, hourly from cron. Hourly because
schools keep their own timezones - midnight in Mumbai is not midnight in
Dubai - and a daily job would close one school's trips hours late or, worse,
while a bus was still out.

- **Cancelled, not ended.** Ending marks everyone who never boarded as
  absent and tells their guardians. At two in the morning, about a trip
  nobody watched, that would be inventing a fact and texting it to parents.
  A cancelled trip says only what is true: it was running, nobody closed
  it, the school should look.
- **Ended at the end of its own day**, not when the job happened to run, so
  the record never claims the bus was out until 2am.
- **The transport managers are told** - the admins where a school has none,
  because an alert nobody receives is not an alert. In their inbox and on
  whatever channels the school has on. The guardian transport switch does
  not silence it: that switch is about what parents are told.
- **Only about the last two days.** The first run finds every trip anybody
  ever left open - 196 of them in the dev database, which would have sent
  774 alerts. Older ones are still closed and still audited; nobody is
  asked to look into a bus from March.

## A drop waits for its pickup

*Asked for 2026-10-23.* **Start drop is disabled until the day's pickup has
been started**, with the reason under it: "Starts after the pickup. The drop
takes home the children the pickup brought in." The server refuses it too
(`PICKUP_NOT_STARTED`) - the button only keeps the crew from meeting that
refusal.

A **cancelled** pickup still counts. The morning happened; children who
reached school another way still have to get home, and refusing the drop
would strand them. The rule is about a day where no pickup was ever
attempted, which is the day a drop would end by marking every child absent
and telling their guardians so.

## Home and Profile

*Asked for 2026-10-23.* Two destinations in a bottom bar, which is the whole
app: the trip they are running, and their own details. A bar with one entry
is decoration; with twenty it is the office's sidebar, which is what this
build exists not to be.

## A tablet is a big phone, not a new app

*Asked for 2026-10-23.* Some buses carry a tablet in the cradle rather than
a phone, so the same APK has to look deliberate on a 10-inch screen. Two
changes, and no second layout:

- `android:resizeableActivity="true"`, so Android stops letter-boxing the
  app and hands it the real window — including split screen and a desktop
  window on Chromebooks.
- The crew frame centres its content in a **640dp column**. A trip sheet is
  a list of children's names; stretched across a tablet, each row's name
  sits a hand's width from its buttons, which is how a driver taps the wrong
  child. The bar and the app bar still span the screen, because those are
  the window's furniture, not the content.

There is no tablet layout, no `if (isTablet)`, and no second set of screens
to keep in step — the column is the whole of it. A driver router test pins
it: at 1600x2560 the trip screen is wider than a phone and no wider than
640.

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
