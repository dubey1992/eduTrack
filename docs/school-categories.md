# School categories

Every school is one of four kinds of account. The Super Admin picks it when
creating the school and can change it later; every change is in the audit
log.

| Category | Meaning | In platform figures | SMS and WhatsApp |
|---|---|---|---|
| Live | A paying customer | counted | sent |
| In Trial | Trying the product, until an end date | counted | sent |
| Demo | Kept for showing the product to prospects | not counted | sent, so a prospect sees a real SMS |
| Testing | Our own testing | not counted | never sent |

Decided with the user on 2026-10-29.

## Beside status, never instead of it

`category` says what kind of account a school is. `status` (active or
inactive) still says whether the school may be used at all. A Live school
can be made inactive; a trial school moved to Live changes nothing else.

## Trials

An In Trial school must have `trial_ends_on`. Any other category has none:
moving a school out of trial clears the date in the same save.

- Creating a trial, or moving a trial's end, to a day before today is
  refused: "The trial cannot end before today."
- An ended trial saved unchanged is accepted. Its date being past is the
  warning showing, not a mistake.
- Ending only warns (CLAUDE.md rule 4: payment never controls access). The
  Super Admin dashboard lists active trials that have ended or end within 14
  days, soonest first, and the school list shows "Trial ends in N days" or
  "Trial ended ..." under the category.

## What counts

Live and In Trial schools make every platform figure:

- the Super Admin dashboard: schools, user accounts, money collected,
  payments owing. The Schools card's hint names how many demo or testing
  schools were left out.
- Platform analytics (docs/analytics.md, A7): totals, every monthly figure
  and module adoption. Sign-ins with no school, such as a Super Admin's
  own, are not counted.
- the homepage's "schools" and "students" figures.

Demo and testing schools still appear, labelled, in the Schools list and the
per-school table on Platform analytics, and both can be filtered by
category.

## Messages from a testing school

The send job skips a testing school's SMS and WhatsApp messages with the
reason "Not sent: this is a testing school.", so made-up records never send
anything on School365ai's Twilio account. Email and the in-app inbox still
work.

## Data

`schools.category` is a string, `live` by default and indexed.
`schools.trial_ends_on` is a nullable date. The migration
(`2026_11_08_090000_add_category_to_schools_table`) made every existing
school Live, so nothing real dropped out of a figure. Demo and test schools
are re-tagged by hand.

The API sends `category`, `category_label`, `trial_ends_on`,
`trial_ends_label` (US date) and `trial_days_left` (negative once ended) on
every school. `GET /schools` takes `category` as a filter.
