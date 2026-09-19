# Maps: schools, routes, stops and live trips (plan)

**Status (2026-09-19):** the parts that need no map provider are built -
the Bus Attendant (role, sign-in, route assignment, My Trip, Call Parent),
offline trip marks, stop coordinates, and the bus position endpoints. The
map screens themselves (M1, M2's route map and road paths, M3's trip map)
wait for the Google Cloud keys. Decisions taken with the user on 2026-09-19
are marked *decided*.

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
| **Browser/app key** | the Flutter web app and the Android app, to draw maps | Maps JavaScript API, Maps SDK for Android | HTTP referrers (the production domain, `localhost`) and the Android package + signing SHA-1 |
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
