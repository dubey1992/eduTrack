# Early access signups

A school that likes the look of the marketing page fills in a form; a Super
Admin sees it in the panel and decides what to do about it.

This is the only table in the system that exists **before a school does**. It
carries no `school_id`, belongs to no tenant, and is the only write in the API
that needs no account — which is exactly why it is the one that treats every
caller as a stranger.

## What the form asks

| Field | Required | Why |
|---|---|---|
| School name | yes | who is asking |
| Contact name | yes | who to ask for |
| Contact role | no | useful, not worth losing a lead over |
| Email | yes | how to reply |
| Phone | yes | with a dial code — multi-nation from the first contact |
| City, Country | yes | which market, and which timezone they will need |
| Expected students | **no** | the single most useful number for deciding who to call first, but plenty of schools genuinely do not know, and demanding it loses the enquiry |
| Current software | no | tells you what the conversation is going to be about |
| Message | no | anything else |

## The pipeline

```
New  ──►  Contacted  ──►  Declined
 │            │
 └────────────┴──────►  Converted     (set by the system, never by hand)
```

**Converted is not settable.** It means a school exists, and the only thing
that can make it true is onboarding one — the API refuses it as a manual
status with a message saying so. A list that says "Converted" with no school
behind it is worse than one that says nothing.

Onboarding from a request is one button: **Onboard this school** opens the
normal Add School dialog pre-filled with the name, email, city and country the
school already gave, and creating the school marks the request Converted and
records which school it became. Nobody has to remember.

A converted request outlives the school it became — the school can be deleted
and the request stays, because it is still a record of who asked and when.

## Protecting a public endpoint

- **Throttled**: five a minute per IP (`throttle:early-access` in
  `AppServiceProvider`). More than any school needs, less than any bot wants.
- **Duplicates**: a school submitting the form twice **updates its own open
  request** rather than raising a second one. Their latest answers win — they
  may be correcting a typo — but the request keeps its place in the queue and
  whatever status somebody has already given it. Once declined or converted, a
  new approach is genuinely new and gets its own row.
- **Says nothing about anyone else**: the response is identical whether the
  request was new or an update. "You have already applied" would confirm an
  email address to anybody who guessed one.

## Who can see them

`SUPER_ADMIN` only — including not a Group Admin. Signups are platform
business, the same as onboarding and payments; a school that could read them
would be reading its competitors' enquiries.

## Endpoints

```
POST  /api/v1/early-access          public, throttled
GET   /api/v1/early-access          Super Admin; ?status= and ?q= to filter
GET   /api/v1/early-access/{id}     Super Admin
PATCH /api/v1/early-access/{id}     Super Admin; status + notes
```

Onboarding from a request is the ordinary `POST /api/v1/schools` with an extra
`early_access_request_id`. Without it, nothing is touched.

## Nobody is emailed

Deliberately, for now. SMS has no provider and SMTP only lands on production
(see `docs/deployment.md`), so a notification would silently do nothing and
look like a bug. The panel is the inbox. Adding a notification later needs no
schema change — `EarlyAccessService::record()` is the one place a new request
comes into being.
