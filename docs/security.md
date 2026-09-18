# Audit and security (Phase 21)

Decided with the user on 2026-09-18 and built on the Python backend only,
like Phases 19 and 20. Laravel is the frozen reference. It still owns the
schema, so the one schema change here, the lockout columns on `users`, is a
Laravel migration kept identical on MySQL and PostgreSQL.

```
FEATURE: Audit & security hardening
OBJECTIVE: record every change and every sign-in; let admins read it; end sessions; stop password guessing
DATABASE: users.failed_login_attempts, users.locked_until (audit_logs already existed, Phase 19)
API: GET /audit-logs, GET /audit-logs/{id}, GET /auth/sessions, DELETE /auth/sessions/{id},
     POST /auth/sessions/others, POST /users/{id}/unlock
FLUTTER: Audit Log screen, Signed-in devices dialog, Locked badge + Unlock on Users and Teachers & Staff
AUTHORIZATION: audit log - Super/Group/School Admin, own scope; unlock - whoever may (de)activate the account
```

## The audit trail

**Every change is recorded, and so is every sign-in.** One writer,
`school/audit.py`, serves every module. A service says what happened, and the
writer adds who, where and when:

- **Who.** The token authentication tells the writer who is calling. Sign-in
  events name the account themselves, because nobody is authenticated yet.
- **Where.** The connection's own address (`REMOTE_ADDR`). It never uses
  `X-Forwarded-For`, which the client writes itself.
- **What.** For an edit, only the columns that changed, before and after. An
  edit that changes nothing records nothing. A creation records the new row
  and a deletion the old one, minus the bookkeeping columns (`created_at`,
  `updated_at`).
- **Never a secret.** Anything named like a password or token is dropped. A
  password change is recorded as having happened (`user.password_set`),
  without the password.
- **Next to the change.** A multi-row write (a register, a payroll run, a
  leave decision) runs in a transaction, and its entry is written inside it,
  so a rolled-back change leaves no entry. A single-row edit and its entry are
  two statements back to back, because requests are not atomic as a whole.

Actions are named `<record>.<what happened>`, for example `student.updated`,
`staff_leave.approved`, `user.locked` or `transport_trip.started`.

| Module | What it records |
|---|---|
| auth | signed in, sign-in failed (with the address tried), locked, unlocked, signed out, password changed or reset, a device signed out |
| users | account created, updated, role changed, password set, activated, deactivated |
| students, staff | created, updated, activated, deactivated |
| attendance, staff_attendance | **one entry per register**: the date and the marks set, and for a correction what each changed mark was before |
| leave | applied, approved, rejected |
| payments, payroll | created, updated; payroll's own actions (Phase 19) |
| timetable | entry created, updated or deleted; periods |
| transport | vehicles, drivers, routes, stops, student assignments; trip started, completed or cancelled |
| academic, holidays, schools | created, updated, deleted; academic year set current; early-access requests |
| teaching, syllabus, announcements, communication | reports filed and reviewed; topics; ticks; announcements; templates and settings |

**Not recorded, on purpose:**
- A trip's individual stops and riders. The trip's own timeline already
  records those, with who and when.
- Marking messages read, which changes nobody's data.
- The attendance marks an approved leave writes. The approval is recorded
  instead.

`EveryWriteIsRecorded` in `test_audit_trail_api.py` sweeps `services.py`. A
method that writes without an audit call, and isn't on its named list of
exceptions, fails the build.

### Reading it

`GET /audit-logs` is newest first and paginated. It filters by `school_id`,
`user_id`, `module`, `action`, `entity_type`, `entity_id`, `from` and `to`, in
the reader's own days, and `?format=csv` exports up to 10,000 rows.

| Who | Sees |
|---|---|
| Super Admin | every school, and platform entries with no school (their own sign-ins, failed sign-ins for unknown addresses) |
| Group Admin | their group's branches |
| School Admin | their school |
| anyone else | 403 |

An entry outside the reader's scope is a 404, never a 403. Nothing edits or
deletes an entry through the API. There is no retention limit yet.

## Sign-in

**Sessions end.**
- A session ends after **7 days without use**, and **30 days after sign-in**
  whatever happens (`SESSION_IDLE_DAYS`, `SESSION_MAX_DAYS`).
- Both limits are measured from the token row's own dates, so tokens that
  Laravel issued, which have no `expires_at`, end on the same terms.
- An expired token is deleted when it is next presented.

Each session is named after the device it was issued to, for example "Chrome
on Windows" or "the app on Android". The *Signed-in devices* dialog lists
them, and signs out any one of them or all but this one.

A session also ends in these cases:

| Event | Sessions ended |
|---|---|
| The user changes their password | every other session |
| A password reset | all |
| An administrator sets a new password, role or email | all |
| The account is deactivated | all |

**Lockout.**
- **10 wrong passwords in a row lock the account for 15 minutes**
  (`LOCKOUT_ATTEMPTS`, `LOCKOUT_MINUTES`).
- While locked, even the right password gets `423 ACCOUNT_LOCKED`, with the
  minutes left.
- The counter lives on the user row, so it holds across server processes and
  restarts.
- A good sign-in resets it.
- The lock ends when its time runs out, when the user resets their password,
  or when an administrator presses *Unlock*. Whoever may deactivate an
  account may unlock it, and nobody may unlock themselves.
- The per-minute sign-in throttle still applies on top of this.

**Passwords.**
- A new password needs 8 or more characters, with a letter and a number, and
  must not be on Django's list of 20,000 common passwords.
- The rules apply wherever a password is chosen: creating a user or staff
  member, an admin setting one, changing your own, and a reset.
- They never apply to signing in, so existing passwords keep working until
  their owners next change them.
- Staff import still generates its own 14-character temporary passwords, and
  those accounts must change them on first sign-in.

## Hardening

- **DEBUG is off unless `DJANGO_DEBUG=true`.** Without DEBUG there is no
  default secret key, and the server refuses to start without
  `DJANGO_SECRET_KEY`. Development sets DEBUG; the test suite needs neither.
- **Headers on every answer:**
  - HSTS for one year (`DJANGO_HSTS_SECONDS`) and an HTTP-to-HTTPS redirect
    (`DJANGO_SSL_REDIRECT`), both on outside development.
  - `X-Frame-Options: DENY`, `nosniff` and `Referrer-Policy: no-referrer`.
  - A Content-Security-Policy that allows nothing, because the API serves
    JSON, CSV and PDF, never a page.
  - `DJANGO_BEHIND_TLS_PROXY=true` trusts `X-Forwarded-Proto`, but only when
    the host really has such a proxy.
- **Throttles count the real address.** `NUM_PROXIES` is 0 unless
  `DJANGO_NUM_PROXIES` says otherwise. DRF's default trusted the whole
  `X-Forwarded-For` header, so one invented address per request would have
  dodged the sign-in throttle.
- **Throttle counts are shared.** They live in a file cache
  (`DJANGO_CACHE_DIR`, default `backend-python/var/cache`), so every worker
  sees them and a restart does not reset them. The host has no Redis.
- **Exports don't run formulas.**
  - A CSV cell that starts with `=`, `+`, `-` or `@` gets a leading `'`, so a
    name typed as `=HYPERLINK(...)` stays text in Excel.
  - A plain number or phone number (`+91 98765 43210`, `-12.5`) is left
    alone.
  - This applies to every CSV the API writes: reports, the audit log and
    import templates.

## Production checklist (Phase 22)

- **Environment:** set `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS` and
  `DJANGO_CORS_ORIGINS`. Leave `DJANGO_DEBUG` unset.
- **Proxy:** confirm whether the cPanel host puts a proxy in front of the app.
  If it does, set `DJANGO_NUM_PROXIES`, and `DJANGO_BEHIND_TLS_PROXY` if it
  terminates TLS.
- **Cache:** make `DJANGO_CACHE_DIR`, or the default `var/cache`, writable by
  the app and not web-served.
- **HSTS:** serve over HTTPS before turning HSTS on. It is sticky in browsers
  for a year.
