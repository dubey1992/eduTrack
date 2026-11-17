# School logo

Decided 2026-11-17. Built the same day.

## What it is

Every school uploads its own logo. A school's **profile is complete once it has one**.

- **Who uploads it.** The School Admin (and a Group Admin, for a branch) under **Settings → School Profile**. A Super Admin can set any school's logo from that school's page under Schools.
- **The reminder.** While the school has no logo, a School Admin sees **"Add your school's logo"** at **every sign-in**. "Remind me later" closes it until the next sign-in. There is no "don't show again", because the logo is required. Teachers and other staff are never asked.
- **The banner.** Until the logo is uploaded, the dashboard says "Your school profile is not complete", with an **Upload logo** button.
- **The setup guide.** It gains a first step, **School logo**, so it now has seven steps.
- **Where the logo shows.**
  - At the top of the side panel for everyone at the school, with the school's name.
  - In the Teacher app's header.
  - On the school's PDFs: receipts, payslips, report cards and statements.
  - The school's initials show until there is a logo.

## Rules

- PNG or JPEG, 2 MB at most. The file is decoded and re-encoded with Pillow, scaled to at most 800 px, and stored under `school-logos/` (`school/school_logo.py`, reusing `school/photos.py`). The file's name and claimed type decide nothing.
- `GET /api/v1/schools/{id}/logo` can be read by anyone in the school's scope: its staff, its group's admins, and Super Admins. Anyone else gets a 404, the same answer as a school with no logo.
- `POST` and `DELETE` on the same address are for the school's administrators and Super Admins. Someone else at the school gets a 403; someone outside the school gets a 404. Both changes are audited (`school.logo_changed`, `school.logo_removed`) without the image.
- `/me` and the sign-in response carry `school_logo_url` and `school_profile_complete`. The school record carries `logo_image_url` and `profile_complete`.
- `schools.logo_url`, the web address typed in before uploads existed, is still read by the PDFs when there is no uploaded logo. It does not complete the profile.

## The side panel

Also asked for 2026-11-17:

- The fold button sits at the left of the top bar, and **Ctrl + B** does the same.
- The choice is remembered on the device.
- While the panel is folded, clicking an area's icon pops up that area's screens, and the panel stays folded.
