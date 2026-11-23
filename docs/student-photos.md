# Student photos

Asked for 2026-11-23. Plan only, nothing built yet. The owner settled
**D1-D4** the same day; all four went the recommended way (see the end).

## Why

A student record has no photo today. Only staff accounts carry one
(`users.photo_path`, docs/profile.md). The Students list shows names alone.
The admit card (examinations/card_pdf.py) and the Classic report card
(report_card_classic.py) print an empty "Student photo" box, and a code
comment says the product "does not hold" one yet.

## What it does

1. **One photo per student**, added or changed from Add / Edit Student and
   removed from the same place.
2. **Bulk upload by admission number.** Under Students -> Bulk upload, a new
   "Student photos" choice:
   - Pick many JPEG or PNG files at once. Each file is named after the
     student's admission number, e.g. `ADM-1042.jpg`.
   - A preview lists each file with the student it matches: name, class and
     section, and whether it replaces a photo already there.
   - Files that match nobody, and two files for one student, are listed
     apart and are not uploaded.
   - "Upload N photos" sends the files, ten to a request (the host runs the
     API as CGI, and small requests keep it answering - see
     project_phase22_live_deploy), with a progress bar.
   - It ends with a summary: added, replaced, skipped and why.
3. **Shown where a student is recognised:**
   - The Students list, as a small round photo, or the initials when there
     is none.
   - Find a student, on the web and in the staff app.
   - The student's own dialog.
4. **Printed** in the photo box of the admit card and the Classic report
   card. Where there is no photo, the box stays as it prints today.

## Database

One migration (Laravel migrations remain the schema source of truth;
the Django model is unmanaged):

| Table | Column | Type | Notes |
|---|---|---|---|
| `students` | `photo_path` | `VARCHAR(255) NULL` | A storage path, never a URL. Null means no photo. |

There is no new table. A photo is one value of the student, as `photo_path`
is for a user. Only the current photo is kept: replacing a photo deletes the
old file, which is what a school expects when it retakes class photos.

## Storage and safety

This reuses school/photos.py, the profile photo code:

- **Checking:** the bytes are decoded with Pillow, so only a real JPEG or
  PNG is accepted. They are then re-encoded, which leaves EXIF data, GPS and
  anything appended to the file behind. Decompression bombs are refused,
  and each file may be at most 5 MB (raised from 2 MB in P2).
- **Size and shape:** scaled to at most **600 px** on the longer side, enough
  for the printed box at 300 dpi. Profile photos are 512 px. With D2, the
  photo is cut to passport shape first.
- **Where it is kept:** a random name under `student-photos/`, through
  Django's storage API. That is local disk today, outside anything the web
  server serves, and S3 later is a settings change.
- **How it is served:** only through
  `GET /api/v1/students/{id}/photo?v=<hash>`. The `v` changes with each new
  photo, so a cached copy is never shown stale. The answer is the same 404
  for "no photo" and "not yours to see", so nobody can learn whether another
  school's student has a photo.

## API

| Method and path | What it does | Who may |
|---|---|---|
| `POST /students/{id}/photo` (multipart `photo`) | Adds or replaces the photo | `StudentPolicy.update` |
| `DELETE /students/{id}/photo` | Removes the photo | `StudentPolicy.update` |
| `GET /students/{id}/photo` | The image | `StudentPolicy.view` |
| `POST /imports/student-photos/preview` (JSON: file names) | Matches names to students; no bytes sent | `StudentPolicy.create` |
| `POST /imports/student-photos` (multipart, up to 10 files) | Stores each matched file; one result per file | `StudentPolicy.create` |

Student resources gain `photo_url`: the path above with its `v`, or null.

The school is always the signed-in person's. A Super Admin names one, as on
every other import, and a `school_id` from anybody else is ignored. The
preview and each batch match admission numbers only inside that school.

Bulk upload is allowed for whoever may add students (School Admin and Super
Admin by default), the same rule as the spreadsheet import in docs/imports.md.
See D3 for teachers.

Each file in a batch is judged on its own. A bad file (not an image, too
large, or matching no student) is reported and the rest are still kept.
Unlike the spreadsheet import, this is not all-or-nothing: photos do not
depend on each other, and a school with one blurry file should not have to
upload the other 499 again.

## Matching a file name to a student

- The name before the extension is compared with the admission number,
  ignoring capitals and spaces at either end.
- **Admission numbers can contain `/`** (the demo school uses `SPHS/26/01A01`),
  and a file name cannot. So `/`, `-` and `_` count as the same character:
  `SPHS-26-01A01.jpg` and `SPHS_26_01A01.jpg` both match `SPHS/26/01A01`.
  See D1.
- Inactive students match too, since a school may photograph a returning
  student. Students of other schools never match.

## Audit

Adding, replacing and removing a photo are logged as a change to the student
(`module: students`, `action: photo_updated` or `photo_removed`). The log
holds no image, only that the photo changed. A bulk upload writes one audit
row per student, plus one summary row ("42 photos uploaded").

## Flutter

- `StudentAvatar`: a photo or the initials, fetched with the signed-in
  person's token. It reuses how `UserAvatar` loads a staff photo.
- **Add / Edit Student:** a photo field. On the web this chooses a file; on a
  phone it takes a photo with the camera or picks one from the phone's
  photos, through image_picker, which the app already has.
- **Students list:** the avatar beside each name.
- **Find a student:** the avatar, on the web and in the staff app.
- **Bulk upload dialog:** the "Student photos" type, with three steps (pick,
  check, upload) and a progress bar.
- Every screen keeps its loading, empty and error states. A refused file
  shows the server's own sentence.

**No new dependency.** Choosing several files at once uses image_picker's
`pickMultiImage`, which already works on Android and the web.

## Tests

### Backend

- **Single photo:**
  - A JPEG and a PNG are accepted and re-encoded. A non-image, a file over
    5 MB and a decompression bomb are refused with a sentence.
  - Replacing a photo deletes the old file, and removing one clears the path.
  - The resource carries `photo_url`, and its `v` changes with each photo.
- **Who may (ALLOW / DENY):**
  - A School Admin may set a photo; a teacher of another section may not;
    another school's admin gets a 404.
  - Reading: a teacher of the class may; a teacher of another class, and
    anybody from another school, get a 404 indistinguishable from "no photo".
  - An accountant may not upload in bulk.
- **Bulk:**
  - The preview matches, flags unmatched files and catches two files for
    one student.
  - `/` matches `-` and `_`, and capitals do not matter.
  - Another school's admission number never matches.
  - A batch keeps its good files when one file is bad.
  - More than 10 files is refused, and a Super Admin names the school.
- **Printing:** the admit card and the Classic report card carry the photo
  when there is one and the box when there is not, with
  `pdf_design.style_errors` = 0.
- **Audit:** the rows are written, and they contain no image bytes.

### Flutter

- The avatar shows the photo or the initials.
- The edit dialog adds, replaces and removes a photo, and shows a refusal.
- Bulk dialog:
  - The preview shows matched, unmatched and duplicate files.
  - The upload button counts only matched files.
  - It shows progress.
  - The summary shows added, replaced and skipped.
  - A failed batch can be tried again.
- Notifier unit tests for the bulk flow, with the repository mocked.

### Integration

Admin -> Students -> Bulk upload -> photos -> check -> upload -> the list
shows the photos. This runs against the test database, with a visible
window.

## As built - P1 (2026-11-23)

- **Changing a photo** from another school, or by a role that may not,
  answers **403**, the same as every other change to a student. Only
  *reading* the image answers 404 for "not yours", so the image cannot tell
  anyone whether a photo exists.
- **The photo is set from Edit Student**, saved the moment it changes (like
  My Profile), not from Add Student: a photo needs the student to exist
  first. Add the student, then open them and add the photo.
- **Class teachers:** the server lets a class teacher set photos for their
  own section (D3). The web app only opens Edit Student for people who
  manage students, so a teacher's way in arrives with P3, in the staff app.
- **The avatar** reuses `UserAvatar`, the staff photo widget. It already
  takes any authenticated photo address and falls back to the initials, so
  no separate `StudentAvatar` was needed.

## As built - P2 (2026-11-23)

- **"Upload Photos"** sits beside Bulk Upload on the Students page. It is
  web only, like Bulk Upload: the Android app has no way to choose many
  files.
- **Up to 5 MB a photo**, single or bulk, instead of the profile photo's
  2 MB. Class photos come off a camera or a phone at 3-5 MB, and every one
  is cut down to 600 px anyway. The app holds back a larger file before
  sending it.
- **Batches are at most 10 files and about 10 MB**, whichever comes first,
  so a request stays small on the CGI host. A failed batch pauses the
  upload. What was sent is kept, and "Try again" sends only the rest.
- **Files are read one batch at a time**, never all at once, so a whole
  school's photos do not have to fit in the browser tab's memory.
- **Held back at the preview**: not JPEG/PNG by name, no matching student,
  two students matching the same name (`ambiguous`), two files for one
  student (`duplicate`, both held back), or over 5 MB. Each is shown with
  its reason.
- **The server judges every file again** when it arrives. One bad file is
  answered `skipped` with a reason, and the rest of the batch is kept.
- **Audit:** each student's photo is logged as `student.photo_changed`, and
  each batch adds one `student_photos.bulk_uploaded` row with its counts.

## As built - P3 (2026-11-23)

- **Admit card:** the photo is printed in the box at 72 x 96 px. A black-and-
  white card prints it in grey. With no photo, or a stored file that has
  gone missing, the box prints its "Student photo" words as before.
- **Classic report card:** the photo is printed in the box at 60 x 80 px, or
  "STUDENT PHOTO" as before. The Standard progress report is unchanged.
- **Register (D4):** the server's register carries each student's
  `photo_url`, and each row in the staff app shows the photo or the
  initials. The class list kept on the phone for no signal holds no photo,
  so a register opened offline shows the initials.
- **Find a student:** the photo is beside each name. A teacher - whose list
  holds only their own section - and the school's admins get a "Photo"
  button that opens the same photo control as Edit Student (D3). The
  server still decides: a teacher of another section is refused.
- **One photo control:** `StudentPhotoField` saves through the repository
  and reports the changed student back. Edit Student puts it in the
  Students list; Find a student asks for its list again.
- **No new automated end-to-end test.** The integration tests start the
  real app, where the photo picker cannot be replaced, so they cannot
  choose a file. The flows were instead driven in a real browser against
  the local API: one photo (P1), and bulk upload with matching, held-back
  files and replacing (P2).

## Slices

1. **P1 - one student's photo:** the migration, the model, the endpoints,
   the resource, the avatar in the list, the edit dialog and the tests.
2. **P2 - bulk upload by admission number:** the preview and the batches,
   the dialog and the tests.
3. **P3 - on paper and on the phone:** the admit card, the Classic report
   card, Find a student in the staff app, and (if D4) the register.

Each slice is deployed only with the owner's go-ahead. P1's migration has to
be applied on the live database before P1's code goes live.

## Decisions (settled 2026-11-23)

All four taken as recommended: **D1** `/`, `-` and `_` count as the same;
**D2** cut to a 3:4 passport shape, centred; **D3** a class teacher may set
photos for their own section one at a time, while bulk upload stays with
admins; **D4** photos go beside names in the staff app's register, in P3.

As they were asked:

- **D1 - file names for admission numbers with `/`:** treat `/`, `-` and `_`
  as the same (recommended), or require the school to rename its admission
  numbers' files some other way?
- **D2 - shape:** cut every photo to a 3:4 passport shape on upload, centred
  (recommended, so it fills the printed box), or keep the photo's own shape
  and fit it inside the box?
- **D3 - teachers:** may a class teacher add or change photos for their own
  section, one at a time (recommended - they take the class photo)? Bulk
  upload stays with admins either way.
- **D4 - the register:** also show the photo beside each name in the staff
  app's register, to help a new or substitute teacher (later, in P3), or
  leave the register as it is?

Not in this plan: Family app parents uploading their child's photo (the
Family app is not released), face recognition, and photo ID cards.
