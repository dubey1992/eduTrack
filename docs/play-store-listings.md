# Google Play listings and data safety - drafts

**Status (2026-11-18): drafts for the product owner (docs/mobile-apps-review.md,
M0, item 9.3).** Text for the Play Console, and the Data safety answers, for
the two apps not yet listed: **School365ai Driver App** (the crew's app; its
icon reads "School365ai Bus") and **School365ai Family**. Everything here is
drawn from what the apps actually ask for and send - the Android manifests,
the plugins in `pubspec.yaml`, and the API. Items marked **to confirm** need
the owner or a lawyer; the privacy policy itself still needs the legal review
noted in docs/driver-app.md (D6.1).

---

## School365ai Driver App (`com.school365ai.app`)

**App name (Play, max 30):** School365ai Driver App
**Icon label on the phone:** School365ai Bus (set in the app, decided 2026-11-18)
**Category:** Education *(alternative: Maps & Navigation - to confirm)*
**Short description (max 80):**
> Run your school bus trip: stops, children on board, and live location.

**Full description:**
> School365ai Driver App is for the drivers and attendants of school buses
> run with School365ai. Your school office gives you a setup code; you sign
> in once with your mobile number and a 4-digit passcode.
>
> - See today's routes and start the pickup or drop trip.
> - Mark each child boarded, dropped or absent - the school and the family
>   are told straight away.
> - Find a child quickly by name, class or voice.
> - Turn-by-turn directions to the next stop.
> - Share the bus's location with the school while the trip runs, even with
>   the screen off. Sharing stops when the trip ends.
> - Works with a weak signal: marks are saved on the phone and sent when the
>   signal comes back.
> - One SOS button tells the school office at once.
>
> The app needs a School365ai account from your school. It is not for
> parents - families use School365ai Family.

**Contact email:** **to confirm** (a support address the owner reads)
**Privacy policy:** https://school365ai.com/privacy

### Data safety - Driver App

| Data type (Play's names) | Collected | Shared with third parties | Why | Optional? |
|---|---|---|---|---|
| Location - **Precise location** | Yes, only while a trip is running and "Share my location" is on | No | App functionality (the school sees where its bus is) | Yes - the crew member can switch it off |
| Personal info - **Name** | Yes (the school creates the account) | No | Account management | No |
| Personal info - **Phone number** | Yes (the sign-in number) | No | Account management, app functionality | No |
| App activity - **Other actions** | Yes: boarding, drop-off and absence marks, trip start and end, SOS | No | App functionality | No |
| Device or other IDs | Yes: a notification token, once push is switched on | No | App functionality (notifications) | No |
| Audio - **Voice or sound recordings** | **To confirm.** Voice search uses Android's own speech recogniser; the app keeps only the words, never the recording, and sends nothing to School365ai. Google's service may process the audio. Likely answer: not collected by the app | No | Search | Yes |

- **Background location:** the app does **not** request background location.
  It keeps a visible "Trip in progress" notification (a foreground service)
  while sharing, which Play treats as foreground use. The Console's
  location-permission declaration should say: *location is used only during
  a school bus trip that the user starts, with a persistent notification,
  so the school can see the bus.*
- **Data about children:** the app shows children's names and classes on the
  route and records their boarding. The app is not directed at children and
  is used only by school staff. **To confirm** how to describe this in the
  Console's "Target audience" (likely: 18+ only, not designed for children).
- **Encrypted in transit:** Yes (HTTPS only).
- **Deletion:** data belongs to the school; a crew member asks their school
  office, and the school deletes the account in School365ai. **To confirm**
  whether a deletion-request web address is also needed (Play asks for one
  when users can create accounts in the app - here only schools create them).

---

## School365ai Family (`com.school365ai.family`)

**App name (Play):** School365ai Family
**Category:** Education
**Short description (max 80):**
> Your child's school day: attendance, bus, fees, results and school notices.

**Full description:**
> School365ai Family is the parents' app for schools that use School365ai.
> Your school gives you a setup code; you sign in with your mobile number and
> choose a passcode. One sign-in covers all your children at that school.
>
> - Today at a glance: was your child marked present, is the bus on its way,
>   what is due next.
> - Attendance by month, with any note from the teacher.
> - The school bus: route, stop and times, and its live position during your
>   child's trip.
> - Fees: what is due and paid, receipts and the year's statement as PDFs,
>   and how to pay the school.
> - Results, report cards and admit cards.
> - School notices, with a Yes/No reply when the school asks.
> - Tell the school about an absence, or ask the class teacher to call you.
>
> The app needs your school to use School365ai. Your school decides what is
> switched on.

**Contact email:** **to confirm**
**Privacy policy:** https://school365ai.com/privacy

### Data safety - Family

| Data type | Collected | Shared | Why | Optional? |
|---|---|---|---|---|
| Personal info - **Name** | Yes (from the school's records) | No | Account management | No |
| Personal info - **Phone number** | Yes (sign-in) | No | Account management | No |
| Photos | Yes, only if the parent attaches one to an absence note | No | App functionality | Yes |
| Messages - **Other in-app messages** | Yes: absence notes, call requests, Yes/No replies to notices | No | App functionality | Yes |
| Financial info - **Other financial info** | **To confirm.** The app *shows* fee dues, payments and receipts from the school; it collects no card, bank or UPI details and takes no payment | No | App functionality | - |
| Device or other IDs | Yes: a notification token, once push is switched on | No | App functionality | No |
| Location | **No** - the Family build removes every location permission | - | - | - |

- **Data about children:** the app shows a child's attendance, results, fees
  and bus. It is for parents, not children. **To confirm** the target
  audience answer (likely 18+); a student sign-in (parked, F6) would change
  this and need Play's Families policy.
- **Encrypted in transit:** Yes.
- **Deletion:** a parent asks the school; **to confirm** a deletion-request
  address, as above.

---

## Still needed from the owner before upload

1. A support contact email for both listings.
2. The legal review of https://school365ai.com/privacy (D6.1), checking it
   covers bus location and data about children.
3. Answers to the **to confirm** items above.
4. Screenshots: taken from the test phones during the GPS test
   (docs/phone-gps-test.md) - at least two per app, 1080 px wide.
5. A feature graphic (1024 x 500) per app.
