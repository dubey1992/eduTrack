# Demo requests

A school that wants to be shown the product asks for a demo from the
marketing page. A Super Admin sees the request in the panel, books a time
and marks how it went. This was decided on 2026-10-29. Early access
([early-access.md](early-access.md)) is a separate thing:

- Joining early access asks for an account.
- Asking for a demo asks for half an hour of a person's time on a particular
  day.

The two are followed up differently, so they are kept in separate lists.
Like early access, a demo request belongs to no school. Its table
`demo_requests` carries no `school_id`, and asking needs no account.

## On the page

"Request a Demo" appears in three places, each next to "Join Early Access":

- the top bar: Login, then Request a Demo (outlined), then Join Early
  Access (solid). The demo button sits in the bar's flexible middle and
  shows only if it fits whole, with the section links giving way first. On
  a phone it is left out, and the hero's own button is the way in;
- the hero: Join Early Access, then Request a Demo;
- the blue closing band: both buttons.

Each label is an editable homepage key: `nav.demo`, `hero.demoButton` and
`cta.demoButton`. They are declared in
`school/marketing.py`, and their defaults live in `marketing_defaults.dart`.

## What the form asks

| Field | Required | Why |
|---|---|---|
| Your name, School name | yes | who is asking |
| Email | yes | how to reply |
| Phone | yes | with a dial code, since schools are multi-nation from the first contact |
| City | no | useful, but not worth losing the request over |
| Country | yes | which market they are in |
| Roughly how many students | no | helps decide who to call first |
| Preferred day | yes | today up to six months ahead |
| Time of day | no | morning, afternoon or evening, in their own timezone |
| Message | no | what they would like to see |

The visitor's **timezone** is not asked for. The browser supplies it
(`Intl.DateTimeFormat().resolvedOptions().timeZone`), because "morning" in
Lagos is not morning in Delhi. The server keeps it only if it names a real
zone, and otherwise drops it without refusing the request.

## The pipeline

```
New  ──►  Scheduled  ──►  Done
 │            │
 └────────────┴──────►  Declined
```

All four statuses are set by hand, with notes, on the Super Admin's
**Demo Requests** screen.

## A second request from the same address

This works as it does for early access. While the first request is open
(New or Scheduled), a second one from the same email does not create a new
row:

- It fills in only fields that were blank, and never overwrites an answer.
  Nobody proves they own the address on a public form, so a later
  submission must not be able to rewrite someone else's request.
- What the second request said goes to the audit trail as
  `demo_request.asked_again`.

Once a request is Done or Declined, the same address can ask again.

## The Super Admin is emailed

Unlike early access, a new request emails every active Super Admin. The
email lists:

- the preferred day, part of day and timezone;
- the contact's phone, place and student count;
- their message, if any.

"Reply" in that email goes to the school.

The email is sent through the job queue, so the visitor never waits on a
mail server. It uses the SMTP settings in force, falling back to the
server's own.

A repeat request sends no email.

## Protection

The form is public and throttled to 5 a minute per address
(`DemoRequestThrottle`). That limit is counted separately from the early
access form's. Reading and updating the list is for the Super Admin only.

## Endpoints

```
POST  /api/v1/demo-requests          public, throttled
GET   /api/v1/demo-requests          Super Admin; ?status= and ?q= to filter
GET   /api/v1/demo-requests/{id}     Super Admin
PATCH /api/v1/demo-requests/{id}     Super Admin; status + notes
```
