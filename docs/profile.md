# My Profile

Decided with the user on 2026-09-19 and built on the Python backend and the
Flutter app only. Laravel still owns the schema, so the one column is a
Laravel migration (`2026_09_29_100000_add_photo_path_to_users_table`).

```
FEATURE: My Profile - every role keeps their own details, email and photo
DATABASE: users.photo_path (a storage path, never a public URL)
API: GET/PATCH profile, POST profile/email, POST/DELETE profile/photo,
     GET users/{id}/photo; /me and the staff resources gain photo_url
FLUTTER: /profile (from the name chip in the header), UserAvatar in the
  header and the Teachers & Staff list
```

## What a person may change

| Field | Who | Notes |
|---|---|---|
| First name, last name | everyone | required when sent, at most 100 characters |
| Mobile | everyone | the usual `+CC number` format; blank clears it |
| Home address | anyone with a staff record | kept on `staff_profiles`; a Super Admin has none and gets `422 NO_STAFF_RECORD` |
| Sign-in email | everyone | needs the current password - see below |
| Photo | everyone | JPEG or PNG, at most 2 MB |

Everything else stays with administrators, through Users and Teachers &
Staff as before: role, school, status, employee ID, department,
designation, joining date. The profile shows those as "kept by your
school's administrators". The form has no fields for them, so a request
that sends them anyway changes nothing.

**Only yourself.** No profile endpoint takes an id. Each one acts on the
account the token belongs to, so nothing in a request reaches another
person's profile.

## Changing the sign-in email

The email is where a password reset goes, so whoever can change it can take
the account. That is why it asks for the current password even though the
person is signed in: a session left open on a shared staff-room computer
must not be enough.

On success:
- The address is stored lowercase and must be unique whatever its case.
- **Every other session ends**; the one making the change stays signed in.
- **The old address is emailed a notice** (queued) saying the sign-in email
  changed and to contact an administrator if they did not do it. The new
  address is shown only partly (`ne***@example.com`), so the notice gives
  whoever reads the old mailbox nothing to act on.
- The audit trail records old and new address (`user.email_changed`), never
  the password.

## Photos

**Decoded, never trusted** (`school/photos.py`). The file's name and the
type the browser claims both come from the client, so neither decides
anything:

1. Over 2 MB is refused before anything is opened.
2. The bytes are opened with Pillow. Only a real JPEG or PNG passes; a
   renamed text file, a GIF or a script is refused with "The photo must be a
   JPEG or PNG image." Images over 40 megapixels (decompression bombs) are
   refused too.
3. The image is turned upright, scaled to at most 512 pixels on its longer
   side, and **re-encoded**. The stored file is a new one, so whatever rode
   along in the upload is not kept: EXIF with the phone's GPS position,
   bytes appended after the image data, a file that is two formats at once.

**Stored** through Django's storage API under a random name in
`profile-photos/`, on local disk under `var/media` (`DJANGO_MEDIA_ROOT`),
outside anything a web server serves. Moving to S3 later is a `STORAGES`
setting, not a code change. A replaced or removed photo's file is deleted,
and the new file is saved before the old one goes, so a failure part-way
never leaves the account pointing at nothing.

**Served only through `GET users/{id}/photo`**, which needs a signed-in
caller and answers:

| Caller | Sees the photo |
|---|---|
| the person themselves | yes |
| a Super Admin | yes |
| an administrator whose scope covers the person's school | yes |
| anyone else, including a colleague or another school's admin | 404 |

A refusal is a 404, the same as "no photo", so the answer never says
whether a photo exists. The response is `Cache-Control: private` so a shared
cache never hands one person's photo to another. `photo_url` carries a
version taken from the stored file's name, so a new photo is a new address
and the app never shows a stale one.

The Android app has no file picker yet, the same limit as bulk imports, so
photos are uploaded from the web app and the Android profile says so.

## Audit

| Action | When |
|---|---|
| `profile.updated` | name or mobile changed (module `users`), address changed (module `staff`); only changed columns, and nothing for a save that changes nothing |
| `user.email_changed` | old and new address, and how many other sessions ended |
| `profile.photo_changed`, `profile.photo_removed` | never the image |
