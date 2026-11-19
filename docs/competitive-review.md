# School365ai against the market (2026-11-19)

How the Staff, Bus and Family apps and the web app compare with the school
apps schools in India are offered today, and what would make School365ai
the stronger product. Companion to `docs/mobile-apps-review.md` (phases
M0-M12); new ideas here are numbered C1-C10 so they do not clash with it.

**Sources and their limits.** Competitor features come from their own
product pages, app-store listings and review sites (Capterra, G2, app
trackers), not from using their apps. Vendor pages state what is offered,
not how well it works. Treat every competitor line as "they say", and check
before quoting any of it in marketing - the no-invented-claims rule applies
to claims about others too.

## Who we are up against

| Product | Where it is strong | What its users complain about |
|---|---|---|
| **Entab CampusCare** (2,000+ schools, chains) | Everything in one place: parent app with live bus, driver details, delay alerts, WhatsApp and SMS, visitor and leave approvals, "AI" analytics | Custom work said to take months; pricing by quote |
| **MyClassboard** | Admissions CRM, parent app with online fee payment and bus tracking, iOS and Android | App-store reviews call it slow and buggy, a notification that opens to nothing; iOS rating around 2.5 |
| **Teachmint** | Free tier, teacher app, LMS + ERP + content, AI teaching assistant, classroom hardware | Feature depth for transport and payroll is thinner |
| **Fedena** | Cheap, broad module list | Support by email, no WhatsApp, no AI |
| **ClassDojo / ParentSquare** (abroad) | Parent engagement: classroom stories, translation into 90+ languages, permission forms, payments coming | Communication only - no attendance-to-payroll operations |
| New AI-first Indian vendors | WhatsApp bots answering parents in Hindi, Tamil, Telugu and others | Mostly marketing so far; hard to verify |

The common pattern: the big ERPs cover every module but feel slow and
generic; the engagement apps feel good but run nothing. Parents' commonest
complaints across all of them are speed, logins that fail, and alerts that
open to an empty screen.

## Where School365ai is already ahead

These are built and live (or on main), and few or none of the products
above show them:

1. **Honest figures.** Attendance is over the days the register was
   marked, not a raw calendar; working days skip holidays and weekends;
   each figure says how it was worked out (M6, 4.1). Rivals show a
   percentage with no explanation.
2. **Proof, not just status.** Who read the absence note and when, who
   rang back, when an answer reached the school, how many opened a notice,
   and the bus timeline with who marked the child on or off and where
   (M6). Rivals show "Boarded"; we show who said so.
3. **Works with no signal.** The register, teaching reports, marks and
   bus trips all queue on the phone and send when signal returns; a trip
   can even start offline (M4). Most rivals need a connection for every
   tap.
4. **The bus without hardware.** GPS comes from the crew's phone, with
   in-app turn-by-turn navigation, board-everyone-at-a-stop with one undo,
   and a "bus is near" alert. Rivals usually need a GPS box in the bus.
5. **Teaching accountability.** Daily teaching reports, syllabus progress
   per class, HOD monitoring, and staff check-in within 100 m of school that
   gates the teaching report. The ERPs above barely cover this.
6. **Built for chains and countries.** Branches as linked schools, a
   currency for each school (never converted or blended), each school's
   own timezone, per-school module switches and one permissions matrix.
7. **The money side is complete.** Fee credit balance, refunds on numbered
   slips, a date lock on fees, staff advances, payroll with pro-rata unpaid
   days, polished PDFs, and Pay with any UPI app.
8. **Structured parent requests instead of open chat.** Absence notes,
   "please call me" and Yes/No replies land in the right place; teachers
   are not flooded (decision D5). Rivals either have no channel or an
   unmoderated chat.
9. **Safety by design.** App lock, no screenshots on payslips and passcode
   screens, the parent's location never taken, a privacy page that says
   who sees the number (M6).

## Where the market is ahead of us

| Gap | Who has it | Why it matters |
|---|---|---|
| **No iPhone apps** - Android and web only (there is no `ios/` project) | Entab, MyClassboard, ClassDojo | Many parents at the fee levels we target carry iPhones; a school cannot roll out a parent app half its parents cannot install |
| **No online fee payment** (decision D4: show dues, pay at school; UPI only opens the parent's app) | MyClassboard, Entab, ClassDojo (coming) | The school still types every UPI payment in by hand; "pay online" is on every rival's feature list |
| **English only** | AI vendors (Hindi + regional), ParentSquare (90+ languages) | Already our M11; every new screen makes it bigger |
| **No homework or class diary for parents** | All the ERPs | Planned as M8 (homework from the teaching report) |
| **No admissions enquiries** | MyClassboard (admissions CRM), Entab | Admissions are where a school earns; we start at the admitted student |
| **No photos, gallery or events** | ClassDojo, Entab | Parents open the app for pictures; planned M9 and M12 |
| **No assistant that answers parents** | New AI-first vendors | "When is the bus coming / what do I owe / is Monday a holiday" are most office calls |

## How to make it the more powerful product (C1-C10)

Ordered by what it does for winning and keeping schools against what it
costs. C1-C3 close gaps that lose deals; C4-C7 are ours alone; C8-C10 add
reach.

| # | Idea | Builds on | Effort | Needs |
|---|---|---|---|---|
| **C1** | **iPhone builds** of the Family and Staff apps. Flutter already makes them; the work is the iOS project, push through APNs, App Store review and an Apple developer account | Everything in M0-M6 | M | Apple account, a Mac or cloud Mac for builds, owner's decision |
| **C2** | **Fees paid online and recorded by themselves.** A gateway with UPI (Razorpay or Cashfree): the parent pays in the Family app, the receipt is made automatically, the office types nothing. Revisits D4 | Fee receipts, credit balance, refunds, UPI link (6.4) | L | Gateway account, settlement and refund rules, decision on fees |
| **C3** | **Hindi first, then regional languages** - pull M11 forward, Family app first (parents), then the Bus app (crew) | All screens | L | Decision on languages and who checks the translations |
| **C4** | **Safe handover.** Each child has the people allowed to collect them (named, with photo); at the school gate or the bus stop the crew or guard sees who may take the child, and the parent is told who did, at what time and where | Trip events (who marked, where), bus timeline (4.3), guardians | M | DB (authorised collectors), decision |
| **C5** | **The principal's morning page.** One push and email at 8:30: attendance so far, staff absent or not checked in, buses running late, reports still owed yesterday, fees collected yesterday per currency - each line opening its screen | Dashboard, staff reminders (M3), check-in, trips | S-M | Decision on time and recipients |
| **C6** | **Ask the school** - an assistant in the Family app (and later on WhatsApp) that answers only from the school's own records: dues, the bus's position, holidays, exam dates, today's timetable. It says where each answer came from and hands over to a call request when it cannot answer; it never makes up policy | Every Family endpoint, call requests, platform WhatsApp (Twilio) | M-L | Decision on AI provider and cost per school; data-protection terms |
| **C7** | **Proof of a whole school day for parents** - one Today card: arrived at school (register), periods taught (teaching reports), homework (M8), on the bus and dropped (trip) - each with who and when | Register, teaching reports, trip timeline | S once M8 lands | - |
| **C8** | **Admissions enquiries** - a form on the school's page, a list of enquiries with follow-ups, and admitted with one tap into a student record | Public site, Request a demo flow, student import | M | DB, decision |
| **C9** | **India's data-protection rules (DPDP Act) made visible** - a consent record for each guardian, a "download my data" and "delete my data" request, and how long the school keeps data, shown on Your privacy | Your privacy (4.5), audit log | M | Legal check of the wording |
| **C10** | **Built for cheap phones and slow data** - measure APK size and cold start on a low-end Android, a data-saver mode (no photos or map tiles unless asked), and say the result plainly in the Play listing | Saved copies (M4) | S-M | A low-end test phone |

## Recommended order

1. **C1 iPhone apps** and **C2 online payment** first: they are the two
   questions a school asks in the first demo, and today both answers are
   "not yet".
2. **C4 safe handover** and **C5 morning page** next: small on top of what
   exists, and nothing like them appears in the rivals' lists - they turn
   "we track the bus" into "we can prove where every child was and who took
   them".
3. Then **M7-M8** as planned, with **C3 Hindi** started as soon as the
   Family screens stop changing, and **C6 Ask the school** once the
   language decision is made (the same answers in Hindi are worth more
   than in English).

**What not to chase:** an LMS, online classes, classroom hardware
(Teachmint's ground), open parent-teacher chat (D5 still holds), and "AI"
labels on reports that are ordinary analytics. Our edge is the school day
run properly and shown honestly, so put the effort there.

## Sources

- Entab CampusCare: [mobile apps](https://www.entab.in/mobile-apps.html), [transport module](https://www.entab.in/entab-blog-gps-track.html), [Capterra](https://www.capterra.com/p/175717/CampusCare/)
- MyClassboard: [App Store listing](https://apps.apple.com/in/app/myclassboard-parent-portal/id1266182786), [Play review analysis](https://kimola.com/reports/transform-parent-school-communication-with-key-insights-google-play-en-in-154044), [app tracker](https://marlvel.ai/apps/myclassboard-parent-portal)
- Teachmint: [Capterra](https://capterra.com/p/163105/Teachmint/), [FitGap](https://us.fitgap.com/products/021746/teachmint)
- Indian comparisons (vendor-written, biased): [Codingclave](https://codingclave.com/blog/best-school-management-software-india-2026), [Schoolites](https://schoolites.com/compare/best-school-management-software-india)
- AI and WhatsApp claims: [Schoolites AI](https://schoolites.com/ai-school-management-software), [E-Cybertech](https://ecybertech.com/blog-ai-school-erp-2026)
- Abroad: [ClassDojo 2026 tools](https://elearningindustry.com/press-releases/classdojo-expands-beyond-the-classroom-with-new-schoolwide-tools), [ParentSquare vs ClassDojo (G2)](https://www.g2.com/compare/parentsquare-vs-talkingpoints-vs-classdojo)
