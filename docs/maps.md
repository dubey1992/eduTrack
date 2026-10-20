# Maps: schools, routes, stops and live trips (plan)

**Status (2026-10-19):** M1 is built. The keys are in, the location picker
places a school, and the Schools map draws them - `maps/config`, address search, place details and
reverse geocoding through the server key; the `AppMap` widget; and the
picker in Add/Edit School; and the Schools map, scoped the way the list is,
with the schools that have no coordinates listed beside it. M2 and M3 are
next.

**Three keys, not two** (corrected 2026-10-19): an API key carries one
*Application restriction*, so the plan's single "browser/app key" is really
two - web (HTTP referrers) and Android (package + SHA-1) - beside the
server key (IP). Only the first two are needed until the APK is built. Everything below that
needs no provider was built on 2026-09-19: the Bus Attendant (role,
sign-in, route assignment, My Trip, Call Parent), offline trip marks, stop
coordinates, and the bus position endpoints. Decisions taken with the user
on 2026-09-19 are marked *decided*.

**Changed from the plan (2026-10-19):** the browser key is handed to
signed-in users by `GET maps/config` rather than baked into the build with
`--dart-define`. It is public either way - the referrer and package
restrictions are what protect it - but this way it can be rotated without
a rebuild, and development and production can use different keys from one
build. The server key still never leaves the server.

### Built so far

| Endpoint | What it does |
|---|---|
| `POST auth/attendant/setup` | mobile + one-time setup code + new passcode registers the phone; returns a session and the device secret, once |
| `POST auth/attendant/login` | mobile + passcode + device secret |
| `GET staff/{profile}/attendant` | the admin's view of an attendant's sign-in: mobile, locked, pending code, devices |
| `POST staff/{profile}/attendant/setup-code` | a fresh 8-digit code, valid 24 hours, shown once |
| `DELETE staff/{profile}/attendant/devices/{device}` | a lost phone: removed, and every session of the attendant ends |
| `GET transport/my-routes` | the attendant's routes with today's pickup and drop trips |
| `POST transport/trips/{trip}/sync` | a batch of marks made on the bus (offline or not), each answered applied / duplicate / rejected |
| `POST transport/trips/{trip}/locations` | positions from the phone of whoever runs the trip |
| `GET transport/trips/{trip}/live` | the latest position, its age, and the next stop with its straight-line distance |

Unlocking after five wrong passcodes is the existing `users/{id}/unlock`.
Positions older than 30 days are deleted by `manage.py
purge_trip_locations`, run daily from cron.

## Why

Every school and branch already records its latitude and longitude, but
nothing uses them. The point of recording them is to put the school group on
a map and to anchor transport to it: routes start or end at the school,
stops sit on the map, and a running trip shows where the bus is.

## What exists today

| Piece | Today |
|---|---|
| Schools and branches | `latitude`, `longitude` (decimal 10,7), optional but validated as a pair; typed in by hand |
| Routes | name, vehicle, driver, status - no path |
| Stops | name, sequence, pickup and drop times - **no coordinates** |
| Trips | started by an admin or the Transport Manager, advanced stop by stop by hand (`current_stop`), boarding and drop events - **no position** |
| Drivers | a record (name, mobile, licence), **not a login** |
| Flutter | no map package |

## Provider: Google Maps or MapTiler

Compared on 2026-09-19 from the providers' own pricing pages (prices in USD,
excluding tax; they change, so recheck before signing up).

| | Google Maps Platform | MapTiler Cloud |
|---|---|---|
| Maps on the web | 70,000 loads/month free, then $2.10 per 1,000 (India billing account); 10,000 free, then $7.00 per 1,000 elsewhere | Free plan is **non-commercial only**; Flex $30/month for 25,000 sessions, then $2.50 per 1,000 |
| Maps in the Android app | **unlimited, free** | counted as sessions, same prices |
| Address search | autocomplete sessions free; Place Details 70,000 free, then $1.50 per 1,000 (India) | 3,000 search sessions in Flex |
| Road paths and times | Routes API, 70,000 free, then $1.50 per 1,000 (India) | **not offered at any tier** - needs a second provider, e.g. GraphHopper (from EUR 69/month for commercial use, 99.5% SLA) |
| Uptime commitment | 99.9% monthly SLA with service credits | SLA only on the Custom (sales) plan |
| Address data in India | strong - most shops, apartments and landmarks findable | built on OpenStreetMap - thinner for Indian addresses, which is what stop search depends on |

**Estimate for 40 schools**, each with about 1,500 web map loads a month
(admins placing stops, the Schools map, staff following trips on the web) and 20 buses
running two trips a school day in the app (about 35,000 app map loads in
all): road paths computed only when stops change, and no API calls per
live-tracking refresh.

| | Google (India billing) | Google (elsewhere) | MapTiler + GraphHopper |
|---|---|---|---|
| Web maps | $0 (60,000 within the free 70,000) | about $350 | about $205, app and web together |
| App maps | $0 | $0 | (included above) |
| Routes and search | $0 at this volume | $0 at this volume | EUR 69 for routing |
| **Month** | **about $0** | **about $350** | **about $280** |

**Recommendation: Google Maps.** For a billing account in India it is both
the cheaper and the more reliable choice: the Android app's maps are free
without limit, the web allowance covers dozens of schools, road routing is
included, the SLA is 99.9%, and its Indian address search is the strongest.
MapTiler is cheaper only for a billing account outside India at high web
volume, and even then needs a second vendor for routing and offers no SLA
below its custom plan. To confirm with Google when the account is opened:
that the India price list covers usage by the platform's schools in other
countries under the same India billing account.

## Decisions

- *Decided* - **A Bus Attendant runs the trip on the bus** (see "The Bus
  Attendant" below), and live position comes from their phone. Admins and
  the Transport Manager can still run a trip, as today.
- *Decided* - **Route lines follow the roads**, computed once when stops
  change and stored, so looking at a map costs no extra API calls.
- *Decided* - **Stops are placed by address search or by clicking the map**,
  then fine-tuned by dragging the pin.
- *Decided* - **The user creates the Google Cloud project and keys**; the
  work is built and tested against a placeholder, and every map degrades to
  the existing list screens when no key is configured.
- Built on the Python backend and the Flutter app, like everything since
  Phase 19. Laravel owns the schema, so new columns are Laravel migrations.

## The Bus Attendant

*Decided 2026-09-19.* A new role, `BUS_ATTENDANT`, for the person on the bus
- the attendant or conductor. A bus with no attendant can give its driver
the same login; drivers remain records otherwise (licence, expiry).

**Sign-in: mobile number and a 4-digit passcode** (*decided*). Four digits
are only 10,000 combinations, so a passcode must not be the only thing
between a stranger and a login. The plan pairs it with **device
registration**, the way banking apps do:
- An admin creates the attendant and gets a one-time setup code (valid 24
  hours). On the attendant's phone the app signs in with mobile + setup
  code, the attendant chooses a passcode, and the device is registered
  with a long random secret stored on it.
- From then on, mobile + passcode only works **on a registered device**;
  the same passcode typed on any other phone or browser is refused.
- 5 wrong passcodes lock the account until an admin unlocks it (not the 15
  minutes a password lock lasts). An admin can revoke a lost phone, which
  ends its sessions at once.
- Web sign-in for an attendant uses the same registration, so a shared
  office computer is not a way in.
- The passcode is stored hashed like a password, never logged.

**What they see:** a phone-first **My Trip** screen with only today's trips
for the routes they are assigned to - start trip, reach stop, mark each
child boarded / dropped / absent, end trip, share location. Nothing else in
the school except every employee's self-service (their own leave, payslips,
profile). Routes gain `attendant_user_id`; the policies limit an attendant
to their assigned routes the way a teacher is limited to their own class.
The permissions matrix gets a Bus Attendant column (Transport: manage).

**Call Parent** (*decided*): each rider's row has a Call Parent button that
opens the phone's dialler with the guardian's number. The number is not
shown in the list. Pressing it is audited (who, which child, when).

**Offline** (*decided*, web and mobile app): buses lose signal, so the trip
keeps working without it.
- Every mark (stop reached, boarded, dropped, absent) is saved on the device
  first, with the time it happened and a unique id, and shown at once.
- A queue sends them when the connection returns, oldest first. The unique
  id makes a resend harmless, so a mark is never recorded twice.
- The server keeps the device's time as when it happened, and refuses a
  mark from more than 12 hours ago, from a clock more than 5 minutes ahead,
  from before the trip started, or for another attendant's route.
- **Once a trip has ended, queued marks for it are refused**, with the
  reason, and the phone lists them under "Not sent" for the attendant to
  read. Accepting marks made before the end would reopen a finished trip -
  its riders already counted, its absences already alerted.
- Starting a trip needs a connection: it happens at the depot, and it
  creates the trip every later mark refers to.
- Guardian alerts go out when a mark reaches the server, so an alert can be
  late by the length of the gap; the message carries the real time
  ("boarded at 7:42 AM").
- GPS points are buffered the same way and uploaded in one batch.
- A banner shows "Offline - 6 marks waiting to send", and signing out with
  marks still waiting asks first.
- The web app keeps working offline only if it is already open (or cached);
  the Android app works from a cold start.

## Two keys, never one

| Key | Used by | APIs | Restrict to |
|---|---|---|---|
| **Web key** | the Flutter web app, to draw maps | Maps JavaScript API | HTTP referrers: the production domain, and `localhost:5000` / `127.0.0.1:5000` for development |
| **Android key** | the Android app, to draw maps | Maps SDK for Android | the Android package name + signing SHA-1 |
| **Server key** | the Python backend only | Places API (New), Routes API, Geocoding API | the server's IP address |

The browser key is visible to anyone who opens the web app, which is how
Google Maps works; the referrer restriction is what protects it. The server
key never leaves the server: address search and route computation go
through the backend (`/maps/...` endpoints), which also lets the backend
cache results and enforce the school's scope. Keys live in the environment
(`GOOGLE_MAPS_SERVER_KEY`) and in the web/Android build
(`--dart-define=GOOGLE_MAPS_BROWSER_KEY`), never in git.

## M1 - Foundation, and the school group on a map

**Flutter:**
- Add `google_maps_flutter` (Google's own package; one codebase for web and
  Android - the dependency rule in CLAUDE.md §6 is met because no existing
  capability draws a map). The web build loads the Maps JavaScript API with
  the browser key from the build define.
- One `AppMap` widget wrapping it, behind a small interface so widget tests
  use a fake (the real map does not render in `flutter test`). With no key
  it shows "Map unavailable - no Google Maps key is configured" and the
  screen carries on without it.
- **Location picker** in Add/Edit School: search or click, drag the pin; the
  latitude and longitude fields stay, filled by the pin, for anyone who has
  exact figures.
- **Schools map**: a Super Admin sees every school; a Group Admin or a
  branch's School Admin sees the parent and its branches; a standalone
  school sees itself. Marker colours tell a parent from a branch; tapping
  one opens the school's card. Schools without coordinates are listed
  beside the map as "not on the map yet".

**Backend:**
- `GET maps/places/autocomplete?q=` and `GET maps/places/{place_id}` -
  proxies to the Places API with the server key, scoped to signed-in
  admins, results cached for a day, throttled per user.
- `GET maps/geocode/reverse?lat=&lng=` - a label for a clicked point.

## M2 - Routes and stops on the map

**Schema** (Laravel migrations, applied to MySQL and PostgreSQL):
- `transport_stops`: `latitude`, `longitude` - decimal(10,7), nullable,
  validated as a pair like schools.
- `transport_routes`: `path_polyline` (text, Google's encoded polyline),
  `distance_m`, `duration_s`, `path_status` (`none` / `ok` / `stale` /
  `failed`), `path_computed_at`.

**Where a route starts and ends:** at its own school (the branch it belongs
to). A pickup trip runs stop 1 -> last stop -> school; a drop trip runs
school -> stop 1 -> last stop. A school with no coordinates cannot have a
road path computed; the route map says so and links to the school's
location picker.

**Screen:** Manage Stops becomes a route map - the stop list on the left
(reorder as today), the map on the right with numbered pins and the school.
Add a stop by searching an address or clicking; drag a pin to move it.
Existing stops without coordinates show as "not placed" until someone
places them; they are skipped when the path is drawn.

**Computing the path:** saving, moving or reordering a stop marks the route
`stale` and queues a `compute_route_path` job (the existing database queue
and cron worker). The job calls the Routes API once with the stops as
waypoints (chunked if a route has more than Google's waypoint limit), and
stores the polyline, total distance and duration, and each leg's distance
and duration. A failure is `failed` with the reason; the map then falls
back to straight lines and offers "Try again".

**Validation:** a stop more than 100 km from its school is refused, which
catches swapped latitude and longitude, the most common mistake with typed
co-ordinates.

## M3 - Trips on the map, with live position

**On the trip screen:** the route's path, the school, and the stops coloured
by state - reached, next, still to come - using the stop marks the trip
already records. This part needs no GPS and works for every trip.

**Sharing location** (only the person running the trip - an admin or the
Transport Manager - and only while it is in progress):
- A "Share my location" switch on the running trip. The phone reports its
  position every 15 seconds while the trip screen is open; it stops when
  the trip ends or the switch is turned off.
- Web uses the browser's Geolocation API (no extra package). Android uses
  `geolocator` for foreground location only - no background location, which
  would need a Play Store policy review; the trip screen has to stay open.
- New table `transport_trip_locations`: trip, latitude, longitude, accuracy
  (m), speed, heading, recorded_at, recorded_by. Points worse than 100 m
  accuracy, out of order, in the future, or for a trip that is not in
  progress are refused.
- `POST transport/trips/{trip}/locations` (a small batch, so a phone that
  lost signal can catch up), `GET transport/trips/{trip}/live` - the latest
  position, when it was recorded, and the ETA to the next stop.

**Watching it:** anyone who may view transport at that school opens the
trip and sees the bus move. The app polls every 15 seconds - shared hosting
has no websockets, and 15 seconds is plenty for a bus. A position older
than 2 minutes is shown greyed as "last seen 3 min ago".

**ETA without a per-minute API bill:** from the stored leg durations - the
remaining share of the current leg, by distance, plus the legs after it,
adjusted for how late the trip is running against the stop times. No Google
call per refresh.

**Privacy:**
- Location is only collected while a trip is in progress and the switch is
  on, and only from the person running it.
- Points are kept 30 days, then deleted by a cron job.
- The audit trail records sharing started and stopped, never each point.
- Stops are pick-up points, not children's homes; the stop screen says so.

## Authorization

| Action | Who |
|---|---|
| See the schools map | Super Admin (all), Group and School Admins (their group) |
| Set a school's location | whoever may edit the school (Super Admin) |
| Place, move, reorder stops; recompute a path | administrators of that school (the fleet stays theirs) |
| See route and trip maps | anyone the permissions matrix gives Transport view, at that school |
| Share location on a trip | whoever may run the trip (admins, Transport Manager) |
| Address search and reverse geocode | administrators |

All of it goes through `permitted()`, so Transport switched off for a school
refuses every map endpoint with `MODULE_DISABLED`, and every endpoint is
scoped to the actor's school or group as today.

## Testing

- Backend: Google calls mocked at the HTTP boundary (as the Twilio and Meta
  adapters are), ALLOW/DENY per school and role, validation edges (half a
  pair, out of range, 100 km, stale and out-of-order points, a finished
  trip), the path job's success, failure and retry, the ETA arithmetic, the
  30-day purge. Contract tests and a sabotage pass.
- Flutter: widget tests against the fake map; the no-key fallback; the
  location switch's permission states (granted, denied, turned off).
- In a browser: once a key exists, a visible-browser run of placing stops,
  seeing the road path, and following a trip; until then the integration
  flows cover everything except the map drawing itself.

## What the user needs to set up (before M1 can be seen working)

1. A Google Cloud project with billing enabled, and a budget alert.
2. Enable: Maps JavaScript API, Maps SDK for Android, Places API (New),
   Routes API, Geocoding API.
3. Create the two keys above with those restrictions.
4. For local development, the browser key needs `http://127.0.0.1:*` and
   `http://localhost:*` as allowed referrers.

Google bills per map load and per API call after a free monthly allowance,
per API. This design keeps calls low on purpose: one Routes call when a
route's stops change, Places only while an admin is typing, and none per
live-tracking refresh.

## Order of work

1. **M1** - map foundation, school location picker, Schools map.
2. **M2** - stop coordinates, route map, road paths.
3. **Bus Attendant** - role, passcode sign-in with device registration,
   route assignment, My Trip screen, Call Parent.
4. **Offline** - the on-device queue for trip marks, then GPS.
5. **M3** - trip map and live location from the attendant's phone.

Each is committed and shown working before the next. M2 needs M1's map
widget; M3 needs M2's stops and path and the attendant's phone.

## What building M1 turned up

Four things that cost time and are worth not rediscovering.

**A stale plugin registrant.** Adding `google_maps_flutter` and rebuilding
the web app is not enough: Flutter's generated `web_plugin_registrant.dart`
is cached per build directory, and the cached one had no
`GoogleMapsPlugin.registerWith`. The map then reports
`TargetPlatform.windows is not yet supported by the maps plugin` - which
reads like an unsupported platform and is really a stale file.
`flutter clean` fixes it.

**`loading=async` finishes before the API is usable.** The script tag's
`onload` fires when the bootstrap arrives; `google.maps` may not exist yet,
and the libraries certainly do not. Creating a map in that gap gives a grey
rectangle and *no error at all*. The loader waits for
`google.maps.importLibrary` to appear and then awaits the libraries by name.

**A platform view needs both dimensions bounded.** A dialog that measures
its content's intrinsic width gets "RenderBox was not laid out" from a map
that will not say how wide it would like to be.

**An empty `gestureRecognizers` set is the default, not a claim.** The map
has to claim the drag with an `EagerGestureRecognizer`, or the scroll view
wins it and the map cannot be panned at all.

**A fifth thing, from M1d:** `BitmapDescriptor.defaultMarkerWithHue` does
nothing on the web. `google_maps_flutter_web` converts only bitmap
descriptors, so a default marker with a hue falls through its switch and
every pin comes out the standard red - while the same code on Android is
correctly coloured. A map coloured that way looks right on a phone and is
flat on the platform the product ships first. The pins are drawn into
bitmaps instead (`map_pin_icons.dart`), which both platforms understand.

Two things this is worth knowing for: the route path in M2 and the bus in
M3 both wanted coloured markers, and any test that compares
`BitmapDescriptor`s is asserting nothing - two built the same way are not
equal, which is how three colour tests here passed against a rule that had
been deleted.

## The Schools map (M1d)

`GET schools/locations` answers with every school the actor may see, as
pins, rather than a page of the list - a pin missing because it was on page
four is a school that looks like it does not exist. It uses the list's own
scoping, so the map can never show a school the list would not.

Three decisions worth keeping:

- **The schools with no coordinates come back too**, and are listed beside
  the map. They are the work the map exists to prompt, and leaving them out
  would hide exactly what somebody opened it to find. On the dev database
  that is all 150 of them, which is the honest answer.
- **A cap of 500, said out loud.** A platform larger than one map of itself
  is told so rather than quietly shown the first few hundred. One row past
  the cap is read to know there are more, and that row is dropped before
  anything is built from it.
- **Half a coordinate is not a pin.** The columns are nullable separately,
  so a half-filled row is reachable however much the form refuses it; it
  counts as unplaced rather than being drawn at (0, 0), off the coast of
  Africa, where it would look every bit as deliberate as a real school.
## What building M2 turned up

The route map works: three real stops on a Pune route, the school at the
end of it, and Google's road between them - 13.1 km, 39 minutes, three
legs. Four things had to be settled first, and three of them are worth
keeping.

### `~` does not mean the same thing on the web

`decodePolyline` refused every road it was given in the browser while
passing twelve tests on the Dart VM, and the map silently drew nothing.
Google's format stores negative steps as odd numbers and undoes them with
`~(result >> 1)`, which is what its own documentation says. But to a
bitwise operator on the web an `int` is 32 bits *unsigned*: `~0` is
4294967295, not -1. Every southward or westward step of the road decoded
as a point thousands of degrees off the earth, the decoder correctly
refused the whole line, and the map fell back to a stand-in that was never
drawn because the note above it said the road was fine.

Two things came out of it:

- The decoder uses `-((result + 1) >> 1)`, which is the same number on
  both platforms, and the accumulator is now bounded at 30 bits - six
  chunks, more than any coordinate on earth needs - so the shift can never
  cross 32 bits on the web either.
- **No test run on the VM can catch this.** `flutter test --platform
  chrome` does not start in this environment (it fails to load even a
  trivial suite), so the guard is a test that reads
  `lib/features/maps/data/polyline.dart` and fails if a `~` appears in it.
  That file holds the only bitwise arithmetic in the whole Flutter app, so
  one reading of one file covers it. If Chrome test runs ever work here,
  that test should be replaced with the real thing.

### Django's `JSONField` assumes `jsonb`, and this schema has `json`

The legs were stored in a `json` column, which Laravel creates and Django's
`JSONField` does not expect. Two separate failures: PostgreSQL's `json` has
no equality operator, so the route list's `Count(distinct=True)` fell over
the moment the column was selected; and Django's own lookups generate
`= 'null'::jsonb`, which `json` refuses.

The legs are now a `text` column the application encodes and decodes, which
behaves the same on MySQL and PostgreSQL. **The mismatch is wider than this
column** - `audit_logs`, `messages`, `module_settings`, `marketing_content`
and `queued_jobs` all have `json` columns reached through `JSONField`, and
they work today only because nothing has yet asked them for equality.
That is its own piece of work and has not been done.

### A dialog sizes itself to its content, and a map has no opinion

`AlertDialog` asks its content how wide it would like to be. The stop list
answered; the map, which fills whatever room it is given, said nothing. The
dialog came out around 700 wide with the map in a sliver of it. The wide
layout now states a width - the lesser of 940 and the window less its
insets - rather than hoping the content asks for one.

### One error that is not ours

`Bad state: RenderBox was not laid out` appears once in the console at
startup, before login and before any map. The debug build names it: it is
thrown entirely inside Flutter's own focus traversal
(`didChangeViewFocus` -> `findFirstFocus` -> `_sortAllDescendants`), which
asks an unlaid-out `RenderStack` for its rect when the browser view takes
focus before the first layout. There are no application frames in the
stack, it is the first error in the console rather than the wreckage of an
earlier one, and the widgets library catches it. Flutter 3.47.0. Left
alone.

## The trip map (M3a)

The first of M3's three slices: **the route a trip takes, and how far along
it is.** The bus sharing its position on the map (M3b) and the ETA from the
stored legs (M3c) are still to come.

`GET transport/trips/{id}` carries `school_latitude`, `school_longitude`
and the same `path` block the route detail carries - through one
`route_path_resource`, so a trip and its route can never draw two different
roads for the same route. Detail only; the list carries neither, and a test
says so.

Three decisions worth keeping:

- **It is drawn from the stop marks, never from the bus.** A trip that
  finished last week reads exactly like one running now, and a trip whose
  attendant never shared a position still shows where it went. The stop
  marks are already recorded for the timeline; the map just reads them.
- **A finished trip has no next stop**, even when it ended with stops
  unreached - which happens. Colouring one of them as "next" would say the
  bus is still on its way there.
- **The map sits under the stop list, not above it.** Whoever is running
  the trip reaches for "Reached" and "Board", and a map between them and
  those buttons is 320 pixels in the way on every phone.

### Both maps now open on what they have to show

A centre and a zoom is a guess, and it is wrong as soon as a route is
longer than the guess allowed for: the far stops sit off the screen, and
somebody who does not think to pan reads it as a route that stops halfway.
`MapBounds.of` takes the smallest box holding every point - the road's
points where there is a road, because a road can swing well outside the box
its stops sit in - and the camera is moved onto it once, when the map is
created. Nothing to frame, or everything in one place, leaves the camera
where the screen put it: a box with no width makes Google pick street
level, which is worse than the guess.

Writing it turned up one piece of dead logic, found by sabotage: a
`points.length < 2` guard that never fired, because one point is already
"everything in the same place". Removed.

## The bus on the map, and when it arrives (M3b, M3c)

The rest of M3. Nothing new was collected: the positions, the endpoints and
the attendant's "Share my location" switch were all built with the Bus
Attendant. What was missing was drawing it and saying something useful
about it.

### The bus

`TripMapCard` watches the same fifteen-second poll the Bus location card
uses - one provider, so the screen asks once however many things on it want
the answer - and passes the position down to `TripMap`, which takes a plain
`BusPosition` and can therefore be tested without a repository behind it. A
trip that is not running is never polled: there is nowhere for its bus to
have moved to, and the stop marks already say where it went.

Two things the browser taught us:

- **Shape, not colour.** The bus started as a near-black pin and its stale
  form as a pale grey one. On a route where the bus has just left a stop,
  that pale grey pin sits directly on the grey pin of the stop it reached,
  and the two are indistinguishable. The bus is now drawn as a **disc** -
  centred on where it is rather than pointing at it from above, which is
  what a position actually is, and unmistakable whatever the colours do.
- **The map does not repeat the card.** The legend first carried a "last
  seen N min ago" line, which put the same sentence on the screen twice -
  the widget tests caught it as two matching widgets. The legend now names
  the bus by its vehicle, and adds the last-seen words only when the pin is
  greyed, because "greyed" means nothing to somebody who has never seen it
  ungreyed.

### The arrival

`GET transport/trips/{id}/live` gains `next_stop.eta_seconds` and
`finishes_in_seconds`, both worked out from the leg durations stored when
the road was computed. **No Google call per refresh**: a trip watched by
five people for an hour would otherwise be twelve hundred calls for a
number that barely moves.

The leg is the road between the stop before this one and this one. How much
of it is left comes from the straight-line distance still to cover, which is
the only thing a position can tell us, capped at the whole leg - a bus that
has overshot and is coming back is further away than the leg is long, and
"longer than the drive itself" helps nobody.

**Null rather than a guess**, and this is most of the rule:

- nobody has shared a position, so there is no "how far left";
- the next stop, or the one before it, is not on the map;
- the route has no road worked out, or its legs cannot be read;
- **the next stop is the first of the run.** A pickup starts wherever the
  bus happened to be; a drop starts at the school, and the stored path runs
  the stops in order and then the school, so the school-to-first-stop road
  is one Google was never asked about. For the same reason a drop's finish
  never counts the last leg back to the school - it does not drive it.

The card says the time where there is one and falls back to the straight
line where there is not, and the next stop's own pin carries it too.
