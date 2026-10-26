# School365ai app - Play release (T8)

The staff app (`com.school365ai`, flavour `teacher`) on Google Play, internal
testing track first. Everything below is ready to paste; the only steps left
are the ones that need the Play Console account.

## What is ready

| Item | Where |
|---|---|
| App bundle, signed with the upload key | `Desktop\School365ai-release\School365ai-1.0.0-1.aab` |
| APKs for installing by hand | `School365ai-1.0.0-arm64.apk` (most phones), `School365ai-1.0.0-arm32.apk` (old phones) |
| App icon 512 x 512 | `Desktop\School365ai-release\store\icon-512.png` |
| Feature graphic 1024 x 500 | `Desktop\School365ai-release\store\feature-graphic.png` |
| Eight phone screenshots, 1080 x 2160 | `Desktop\School365ai-release\store\phone-1.png` ... `phone-8.png` |
| Privacy policy, with a section for this app | `https://school365ai.com/#/privacy` |

**Signing.** The bundle is signed with the School365ai upload key (`CN=School365ai`),
the same key as the Driver app. SHA-1
`47:2C:35:3F:C6:C2:7F:23:C0:16:D8:8B:B6:F6:8D:0B:88:A2:80:2D` - needed for the
Firebase Android app and for any restricted Google key. Enrol in **Play App
Signing** when creating the app; Play then holds the app signing key and this
one stays the upload key. Its keystore and `key.properties` must be backed up
off this machine (docs/driver-app.md, D1.2).

**Rebuilding.** Bump `version:` in `frontend/pubspec.yaml` (`1.0.0+1` now; the
`+N` is Play's version code and must rise with every upload), then:

```
flutter build appbundle --release --flavor teacher -t lib/main_teacher.dart ^
  --obfuscate --split-debug-info=<release folder>\symbols	eacher ^
  --dart-define=API_BASE_URL=https://api.school365ai.com/api/v1
```

Keep each release's `symbols` folder: with `--obfuscate`, a crash report
from a phone is only readable through `flutter symbolize` with the symbols
of that exact build.

## Size (2026-10-27)

What a phone downloads is one processor type's worth. Play cuts it from the
bundle by itself; for installing by hand there is one APK per type.

| App | Before | 64-bit phone (arm64) | Older 32-bit phone | Play bundle |
|---|---|---|---|---|
| School365ai (staff) | 90.2 MB universal APK | 27.6 MB | 25.0 MB | 64.2 MB (was 79.1) |
| School365ai Driver | 88.7 MB universal APK | 36.2 MB | 30.4 MB | 74.5 MB |

How:
- **One processor type per APK** (`--split-per-abi`). The universal APK
  carried 64-bit ARM, 32-bit ARM and x86_64 (emulators only) side by side.
- **The staff app no longer carries the Navigation SDK's native engine**
  (`libgmm-jni.so`, about 9 MB per type), excluded for the teacher flavour
  in `android/app/build.gradle.kts`. The driver app keeps it - turn-by-turn
  needs it. Checked by running the slimmed staff release: sign-in, Today,
  check-in and Department all work, nothing in the device log.
- **Dart code obfuscated and its debug symbols kept outside the app**
  (`--obfuscate --split-debug-info`).

For sideloading, give phones the `arm64` APK; the `arm32` one is for old
handsets that reject it.

Add the four `FIREBASE_*` defines once push is set up (docs/teacher-app.md, T6).

**Screenshots** were taken on the emulator against the demo school. Its
student names repeat and every roll number is 2; for the public listing,
retake them against a school with tidier sample data.

## Store listing

**App name** (30): `School365ai`

**Short description** (80):
`Your school day on your phone: check in, register, reports, marks and leave.`

**Full description**:

```
School365ai puts a school's working day in every staff member's pocket. It
is the phone companion to your school's School365ai account: sign in with the
email and password your school office gave you.

FOR TEACHERS
• Today at a glance - your periods in order, the one under way marked, and
  what is still to do.
• Check in and out at school - one tap, confirmed against the school's
  location, nothing tracked.
• The class register - big Present / Absent / Leave buttons, a running
  tally, and it works without signal: the register is saved on the phone and
  sent as soon as there is a connection.
• Teaching reports - say what each period covered, tick off the syllabus
  topic in the same step, and see when your HOD has reviewed it or sent it
  back with a note.
• Syllabus - every class and subject you teach, with how far it has got.
• Class tests and marks - set a test, enter marks for the whole class, and
  publish the results when everyone is marked.

FOR HEADS OF DEPARTMENT
• Reports from your department waiting for review - mark them reviewed or
  send them back with a note.
• Who in your department is in today, and each teacher's month at a glance.

FOR ALL STAFF
• Leave - apply, and see where each request stands.
• Payslips - read them and have the PDF emailed to you.
• Messages from your school, in one inbox.

School365ai is used by schools; accounts are created by the school office.
There are no ads.
```

**Category:** Education. **Tags:** school management, teachers, attendance.
**Contact email:** the school operator's support address.

## Data safety form

| Question | Answer |
|---|---|
| Does the app collect or share user data? | Collects; does not share with third parties (Firebase only delivers notifications for us - a service provider, not "sharing"). |
| Encrypted in transit? | Yes (HTTPS only). |
| Can users ask for deletion? | Yes - through their school, which owns the account (privacy policy). |
| **Location** - approximate and precise | Collected, not shared. Purpose: app functionality (check-in at school). Not stored: compared with the school's location and discarded; only the distance is kept. Optional - only when the person taps Check in / Check out, and not at all where the school marks staff in the office. |
| **Personal info** - name, email, phone number | Collected (the school creates the account). App functionality, account management. |
| **App activity** - in-app actions | Collected: registers, reports, marks, leave requests the user enters. App functionality. |
| **Device or other IDs** | Collected once push is on: the Firebase notification token. App functionality (notifications). Removed at sign-out. |
| Photos, audio, contacts, files, health, financial info, browsing | Not collected. |
| Ads, analytics, tracking SDKs | None. |

**Permissions in the built app** (read from the release APK with `aapt dump
permissions`): internet and network state; fine and coarse location
(foreground only, at the Check in / Check out tap); notifications, with
Firebase messaging's own receive, wake-lock and Google-services entries. The
Driver app's background location, foreground service, microphone, Bluetooth
and storage permissions are all removed in
`android/app/src/teacher/AndroidManifest.xml`.

Two gaps were found and fixed while preparing this: the staff app's manifest
still **removed** the notification permission (carried over from T0), which
would have silently dropped every push on Android 13 and later; and the
Navigation SDK's storage permission was reaching the staff app.

**Content rating:** a work tool for school staff; no user-generated content
shared publicly, no ads, no purchases. Target audience: **18 and over** (staff,
not students) - which keeps it out of the Families programme.

## Steps in the Play Console (only these need the account)

1. **Create app** - name School365ai, default language English (India), App,
   Free. Accept the declarations.
2. **App signing** - choose Play App Signing (Google-managed key).
3. **Store listing** - paste the text above; upload the icon, the feature
   graphic and the eight screenshots.
4. **App content** - privacy policy URL, the data safety answers above, ads:
   no, content rating questionnaire, target audience 18+, news app: no,
   government app: no.
5. **Testing → Internal testing** - create a release, upload
   `School365ai-1.0.0-1.aab`, add the testers' Google accounts (a few
   teachers and an HOD at one school), roll out.
6. Testers open the opt-in link from the Internal testing page, install from
   Play, and sign in with their school accounts.
7. After a week of real use, promote the same release to **Closed testing**
   and then **Production**.
