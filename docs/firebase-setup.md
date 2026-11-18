# Switching on push notifications (Firebase)

**For:** the product owner, once. **Time:** about 20 minutes.
**Why:** all three phone apps - School365ai (staff), School365ai Bus (crew)
and School365ai Family - send notifications through Google's Firebase Cloud
Messaging. The code is built and waiting; until this is done every build has
push switched off and behaves exactly as it does today
(docs/mobile-apps-review.md, M0).

Nothing here costs money: Firebase Cloud Messaging is free.

## 1. Create the project

1. Go to <https://console.firebase.google.com> and sign in with the
   business Google account (the one that owns the Google Maps keys is best,
   so everything sits in one place).
2. **Add project** → name it `School365ai` → you may switch off Google
   Analytics (not needed) → **Create project**.
   - If it offers to use an existing Google Cloud project, choose the one
     that holds the Maps keys.

## 2. Add the three Android apps

In the project: **Project settings** (gear icon) → **Your apps** → **Add
app** → **Android**, three times, with exactly these package names (they are
permanent and must match the apps):

| App | Android package name | App nickname |
|---|---|---|
| Staff | `com.school365ai` | School365ai Staff |
| Bus crew | `com.school365ai.app` | School365ai Bus |
| Family | `com.school365ai.family` | School365ai Family |

- Leave "Debug signing certificate SHA-1" empty - push does not need it.
- When it offers `google-services.json`, you may download it, but **do not
  put it in the project**: the apps read their keys at build time instead.
- Skip the "Add Firebase SDK" steps - they are already done in the code.

## 3. Send these values

From **Project settings → General**:

- **Project ID** (e.g. `school365ai-1a2b3`)
- **Project number** - this is the **Sender ID**
- **Web API Key** (same for all three apps)

From each of the three apps listed under **Your apps**:

- its **App ID** (looks like `1:123456789012:android:abc123...`) - one per app

These are not secrets in the sense a password is (they ship inside every
app), but keep them out of chat channels anyway; paste them to me directly.

## 4. The server key

This one *is* a secret: it lets the server send notifications.

1. **Project settings → Service accounts** → **Generate new private key** →
   **Generate key**. A `.json` file downloads.
2. Save it on this computer as
   `C:\Users\abhis\Desktop\eduTrack\backend\firebase-service-account.json`
   (that folder is never committed), and tell me it is there.
3. I upload it to the server outside the website folder and point
   `FIREBASE_CREDENTIALS_FILE` at it in the server's `.env`, then delete my
   local copy if you want.

## 5. What I do with them

- Builds get the keys as `--dart-define=FIREBASE_API_KEY=...
  --dart-define=FIREBASE_APP_ID=<that app's ID> --dart-define=FIREBASE_SENDER_ID=...
  --dart-define=FIREBASE_PROJECT_ID=...` - a different App ID per app.
- The server sends a notification as a second copy of an in-app message:
  - staff: leave decisions, reviewed reports, absence notes, call requests,
    announcements;
  - parents: everything that reaches their Notices;
  - bus crew: nothing yet (their messages come with phase M7).
- Test: a leave approval reaches a teacher's phone with the app closed, and
  a notice reaches a parent's.

## If a key ever leaks

- **Server key:** Service accounts → delete that key → generate a new one →
  send it again. Old phones keep working.
- **App keys:** restrict the Web API key in Google Cloud Console → APIs &
  Services → Credentials to the three Android package names.
