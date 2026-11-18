# Real-phone GPS test - School365ai Bus

**For:** whoever carries the phones on a real bus run. **Phones:** one each
of Xiaomi/Redmi/POCO, Oppo/Realme/OnePlus, Vivo/iQOO and Samsung.
**Closes:** docs/driver-app.md D4.4 and docs/mobile-apps-review.md item 9.2.

## What it proves

That each phone keeps sending the bus's position to the school **with its
screen off, in a pocket or a cradle, for a whole run**. Xiaomi, Oppo and Vivo
stop background apps in their own way, which no code can check, so the only
proof is a real run. The app keeps a log of every position it takes; a gap
of more than 3 minutes on a moving bus means the phone paused it.

## Before the day

1. **Install** the test app on each phone: `app-driver-release.apk` (sent
   separately). Allow "install from unknown sources" when asked. It is the
   School365ai Bus app, talking to the live system.
2. **A crew account per phone** in the demo school: in the web app,
   Transport → Crew → the lock icon beside the driver or attendant
   (*Sign-in & phones*) → issue a setup code. Each phone
   registers with the mobile number and that 8-digit code, then picks a
   4-digit passcode.
3. **A test route with no children on it**, one per phone (Transport →
   Routes → Add: a few stops along the real road, that crew member as
   driver or attendant, and *no students assigned*). This matters: boarding
   marks and ending a trip send real SMS to guardians, and ending marks every
   child not yet boarded as absent. With no children on the route, nothing
   is marked and nobody is messaged - the GPS is all that is being tested.
4. **Battery steps:** in the app, the duty screen's battery warning (or
   Trip check → Steps) walks through this phone's own settings. Do them all
   - on Xiaomi especially "Autostart" and "No restrictions".

## On the run

1. Open the app, **Start pickup** (or drop) on the route.
2. Leave **Share my location** on. Allow location "While using the app"
   when asked - that is enough; the app keeps itself running with a
   notification.
3. **Lock the screen** and put the phone in a pocket or the cradle. Do not
   open the app again until the end. Ride at least **30 minutes** of real
   driving, with some stops.
4. Meanwhile, someone in the office opens Transport → Trips → the running
   trip, watches the bus on its map, and notes any time it froze.
5. At the end, open the app and tap **End trip** (with no children on the
   route there is nothing to mark).

## After the run

1. On the duty screen tap **Trip check**.
2. Tap **Share report** and send it (WhatsApp is fine) with the phone's
   brand and model, e.g. "Redmi Note 12, Android 14".
3. Note anything odd: the notification disappearing, the app reopening at
   the sign-in screen, the phone warning about battery.

## Passing

| Check | Pass |
|---|---|
| Longest gap between positions (Trip check) | 3 minutes or less |
| Still waiting on this phone, after signal returns | 0 |
| Office map | the bus moved all the way, no long freeze |
| "Sharing stopped" lines | only at the end of the trip |

A phone that fails gets its battery steps checked and one more run. If it
still fails after the steps, we record that model in the battery help screen
with whatever extra setting fixed it - or as a phone to avoid.

## Results

| Brand | Model / Android | Date | Longest gap | Waiting | Map | Result |
|---|---|---|---|---|---|---|
| Xiaomi / Redmi / POCO | | | | | | |
| Oppo / Realme / OnePlus | | | | | | |
| Vivo / iQOO | | | | | | |
| Samsung | | | | | | |
