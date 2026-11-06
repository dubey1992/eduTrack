# Fewer Menu Items, Tabs Inside: Navigation Plan

**Status (2026-11-06): S2 chosen and built (icon strip + list, prototype colours). Bottom bar, search and "setup screens step back" not built yet.**

## The problem

Every screen is its own entry in the left panel: 8 groups and about 45
entries. A School Admin scrolls past roughly 35 of them. Related screens sit
apart: Fee Setup, Student Fees, Receipts and Discounts are four rows, while
the five transport screens and the seven academic set-up screens fill most of
a laptop screen. People find a screen by reading the whole list, and on a
phone the drawer is a long scroll.

## The idea

The left panel lists **areas** (about 11 for an admin, 6 for a teacher).
Each area opens on a page with **tabs** along the top, one tab per screen
that used to be a sidebar row.

```
+----------------+--------------------------------------------------------------+
| School365ai    | Fees                          [Year 2026-27 v] [Admin] (RM)  |
|                | ------------------------------------------------------------ |
| Dashboard      |  Student Fees | Receipts | Discounts | Fee Setup             |
| Insights       |  ============                                                |
| People         |                                                              |
| Attendance     |   (the Student Fees screen, exactly as it is today)          |
| Teaching       |                                                              |
| Academic Setup |                                                              |
| > Fees         |                                                              |
| Payroll        |                                                              |
| Transport      |                                                              |
| Messages       |                                                              |
| Settings       |                                                              |
+----------------+--------------------------------------------------------------+
```

On a phone the drawer holds the same short list, and the tabs become a strip
under the top bar that scrolls sideways.

## Alternatives (asked for 2026-11-05)

Areas with tabs is one way to shorten the menu. Here are the others worth
weighing. Every one keeps the rules below: same addresses, same
permissions, screens untouched.

### Structures (pick one)

**S1. Areas + tabs across the top** (the idea above).
One click to the area, one to the tab. Tabs show the related screens side
by side. It is crowded when an area has 7 tabs (Academic Setup), so those
scroll.

**S2. Icon rail + second panel** (the Slack, Zoho and Odoo pattern).

```
+--+---------------+-------------------------------------+
|# | Fees          |                                     |
|$ | Student Fees  |   (page)                            |
|@ | Receipts      |                                     |
|% | Discounts     |                                     |
|  | Fee Setup     |                                     |
+--+---------------+-------------------------------------+
```

A thin rail of area icons, and next to it a short list of the chosen area's
screens. The second panel folds away for wide tables. It handles 7 screens
in an area better than tabs, and is familiar from business software. It
takes more width on a laptop, and the icons need labels on hover.

**S3. Accordion sidebar** (smallest change).
Today's groups, but folded: only the current page's group is open. Nothing
moves, so there is nothing to relearn and almost nothing to build. The
panel stays long once a group is open, and it doesn't group related
screens any better than today.

**S4. Top menu with drop-downs** (the classic ERP bar).
Areas across the top, and each opens a menu of its screens. The page gets
the full width. Hover menus don't work on touch screens, and 11 areas don't
fit across a laptop, so it needs a "More". Weak on phones.

**S5. App launcher home** (like Google Workspace or Odoo's app grid).
The home page is a grid of large tiles, one per area, with counts on them
("3 leave requests"). Each tile opens the area with its tabs or panel. It
is the friendliest for non-technical staff, but adds a click for people who
already know where they're going, so it pairs well with search.

**S6. Organised by job, not by module** (the most radical).
Top level: *Today* (what needs doing: register, reports, approvals, fees
due), *People*, *Teaching*, *Money*, *Transport*, *Setup*. "Today" becomes
the main screen for most roles. It is the closest to how a school thinks,
but it is the biggest change for schools already live and needs
retraining.

### Add-ons (work with any structure)

| Add-on | What | Build |
|---|---|---|
| **Search / Ctrl+K** | One box finds a screen, a student, a member of staff or a class. Ctrl+K opens it from anywhere | M |
| **Pinned and recent** | Each user pins their frequent screens to the top of the panel. "Recent" lists the last 5 opened | S |
| **Phone bottom bar** | Home · Attendance · Messages · Search · More, with the rest under More | S |
| **Setup screens step back** | Once the Setup Guide is finished, Academic Setup moves under Settings. Year-once screens stop taking daily space | S |
| **Simple mode** | A per-user switch that shows only that role's daily screens. "Show everything" is one tap away | S |
| **"Today" panel per role** | Dashboard buttons for the jobs each role opens the app for (also in N4) | M |

### Comparison

| | S1 Tabs | S2 Rail + panel | S3 Accordion | S4 Top menu | S5 Launcher | S6 By job |
|---|---|---|---|---|---|---|
| Menu length for an admin | 11 | 11 icons | 8 groups, 1 open | 11 across | 11 tiles | 6 |
| Clicks to a screen | 2 | 2 | 1–2 | 2 | 2–3 | 2 |
| Related screens together | yes | yes | no | yes | yes | yes |
| Areas with 7 screens | crowded | fine | fine | fine | fine | fine |
| Phone | good | adapts (drawer) | as today | weak | very good | good |
| Relearning for live schools | small | small | none | medium | small | large |
| Build | M | M | S | M | M | L |

### Recommendation

**S2 (icon rail + second panel) on desktop and tablet, the bottom bar on
phones, plus Search/Ctrl+K and "Setup screens step back".**
- S2 groups screens like S1, but copes with large areas and keeps wide
  tables wide.
- Search covers people who know what they want.
- The bottom bar is how phone users expect an app to work.
- Moving the year-once setup screens out of daily view cuts the most noise
  for the least work.

S5 (a tile home) can be added later for the least confident users without
changing the rest.

If the owner prefers what is already on paper, S1 (tabs) is a close
second. Everything under "How it is built" applies to either, with the
TabBar swapped for the second panel.

## What does not change (so nothing breaks)

1. **Every address stays the same.** `/fee-receipts` still opens Receipts,
   now as the Fees area with the Receipts tab selected. Bookmarks, links in
   emails, the push notifications that open a screen, the Setup Guide's
   "Open" buttons and every test that navigates by path keep working. A tab
   is just `context.go(path)`.
2. **Who sees what stays exactly the same.** Each tab is the existing
   `NavItem`, so `NavItem.allows()` decides tab by tab: the permissions
   matrix, module switches, and denied roles all keep working. An area with
   no allowed tab is not shown. An area with one allowed tab shows no tab
   bar, and its name in the panel becomes that screen's name (a teacher with
   only My Payslips sees "My Payslips", not "Payroll").
3. **The screens themselves are untouched.** The tabs sit in the shell,
   above the page, so no screen is rewritten.
4. **The router's access check is unchanged.** It still reads `AppNav` and
   its items. Areas only change how the menu is drawn.
5. **The top bar keeps** the year switch, role pill, profile and sign-out.
   The heading shows the area name, and the tab names the screen.

## The areas

| Area | Tabs (in order of daily use) |
|---|---|
| **Dashboard** | Dashboard · Setup Guide (admin, while unfinished) |
| **Insights** | Reports · Analytics · Early Warning |
| **People** | Students · Teachers & Staff |
| **Attendance** | Student Attendance · Staff Attendance · Staff Leave · Biometric Devices |
| **Teaching** | Timetable · Teaching Reports · Syllabus · Class Tests · HOD Reports |
| **Academic Setup** | Classes & Sections · Subjects · Departments · Academic Years · Holidays · Grade Scales · Class Promotion |
| **Fees** | Student Fees · Receipts · Discounts · Fee Setup |
| **Payroll** | Payroll · My Payslips |
| **Transport** | Trips · Routes · Bus Stops · Vehicles · Crew (the bus crew keep My Trip alone) |
| **Messages** | My Inbox · Announcements · Communication |
| **Settings** | Admin Users · Roles & Permissions · Module Settings · Audit Log |

**Super Admin only:**

| Area | Tabs |
|---|---|
| **Schools** | Schools · Payments · Early Access · Demo Requests |
| **Website** | Homepage Content · Website Pages |
| **Platform** | Company Details · Email Settings · Messaging |

**What each role ends up with:**

| Role | Entries today | Areas after |
|---|---|---|
| School Admin | ~35 | 11 |
| Teacher | ~14 | 6 (Dashboard, People, Attendance, Teaching, Academic Setup, Messages) |
| HOD | ~16 | 7 |
| Accountant | ~10 | 5 (Dashboard, Insights, Fees, Payroll, Messages) |
| Super Admin | ~40 | 12 |

## Small touches that make it feel better

- **Remember the last tab.** Opening Fees again lands on the tab used last
  in that area (per user, in the existing KeyValueStore). The plain address
  still always wins.
- **Counts on tabs.** Staff Leave shows the number of requests waiting,
  Teaching Reports the number waiting for review, and Student Fees the number
  overdue. These come from figures the dashboard already loads, so there are
  no extra calls on every page.
- **Keyboard.** Arrow keys move between tabs, and each tab carries its name
  for screen readers.
- **Collapsible panel on desktop.** The shorter list allows an icon-only
  mode, giving tables more width.

## Second step (optional): tabs inside a record

The same pattern inside a single record, replacing today's separate dialogs:

- **A student's page:** Profile · Attendance · Results · Fees · Transport ·
  Class History. Today these are separate dialogs and screens: the
  performance dialog, class history, the fee statement and the transport
  picker.
- **A staff member's page:** Profile · Attendance · Leave · Timetable ·
  Payslips.

Each tab reuses the existing widget and API, so there is no new backend. It
is a separate decision (N3), because it changes how people open a record
rather than only how they find a screen.

## Easier to use, beyond tabs

Asked for the same day: "design and develop the application more easy to use
for customers." Tabs fix finding a screen. These fix what people do once
they are there:

- **Search from anywhere.** A search box in the top bar finds a student, a
  member of staff, a class, or a screen by name ("receipts" opens Fees →
  Receipts). It uses the list APIs that already search, and respects the
  same permissions.
- **"What do I do now" buttons on each role's dashboard.** A teacher sees
  *Take today's register* and *File today's reports*. An accountant sees
  *Record a payment* and *Overdue fees*. An admin sees *Leave waiting (3)*.
  These are the jobs each role opens the app for, one tap away.
- **Empty screens say what to do next.** A screen with nothing in it names
  the step that fills it, with a button (for example "No fee structures for
  2026-27 yet - Copy last year's" once A2 of `docs/automation.md` exists).
- **One way to do each thing.** The same layout everywhere: the main action
  top right, filters in one row, Edit and Delete in the same place on every
  table. A short review pass lists and fixes the screens that drift.
- **Plain words.** The wording is the user's, not the system's, and errors
  say what to do. A pass over labels and messages, starting with the screens
  new schools see first.

These ride on the automation plan: one-tap teaching reports, reminders and
"prepare next year" remove work. Search, the dashboard buttons and clear
empty screens remove hunting.

## How it is built

| Slice | What | Size |
|---|---|---|
| N1 | `NavArea` (label, icon, list of existing `NavItem`s) in `app_nav.dart`. The sidebar draws areas, and the shell draws a `TabBar` of the allowed tabs above the page, with the selected tab taken from the current path. Mobile drawer and scrolling tab strip. | M |
| N2 | Remember the last tab per area, tab counts, the collapsible panel. | S |
| N3 | Student and staff record pages with tabs (if approved). | L |
| N4 | Top-bar search, the dashboard's "what do I do now" buttons, and helpful empty screens. | M |
| N5 | Consistency and wording pass over every screen, new-school screens first. | M |

No backend or database changes for N1 and N2.

**Tests:**
- **The menu for each role.** A widget test per role lists the expected areas
  and tabs. It is built from the same permissions fixture as today's sidebar
  tests, so a matrix change shows up as a failing test, not a hidden screen.
- **A screen with its module switched off** loses its tab, and an area
  emptied that way disappears.
- **Deep links.** Opening `/fee-receipts` directly selects Fees → Receipts.
  Opening a denied path still redirects as today.
- **Single-tab areas** show no tab bar.
- **Navigation.** The existing integration tests (Admin → Students → Add,
  Teacher → Attendance → Submit, and the rest) must pass unchanged. That is
  the proof that nobody's way through the app broke.
- **Live check.** Desktop and phone width in a real browser, before deploy.

## Decisions needed from the user

- **N-D0:** Which structure - S1 tabs, S2 rail + panel (recommended), S3 accordion, S4 top menu, S5 launcher, S6 by job - and which add-ons?
- **N-D1:** Are the areas and names above right? In particular, should
  Staff Leave sit under Attendance (proposed) or be its own area?
- **N-D2:** Should Setup Guide be a Dashboard tab only while setup is
  unfinished (proposed), or always?
- **N-D3:** Build the second step (tabs inside a student's and a staff
  member's record) now, later, or not at all?
