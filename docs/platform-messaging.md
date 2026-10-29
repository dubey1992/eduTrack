# Platform messaging: School365ai sends, schools are charged

Decided 2026-10-29. This replaces per-school Twilio keys
(docs/communication.md, "Providers, and where their keys live"). Nothing is
built yet; this is the plan.

## The decisions

| Question | Decided |
|---|---|
| Whose Twilio account | **School365ai's own**, one account for the platform. Schools never see or enter keys. |
| A school's own account | **Not offered.** Every school sends through the platform and is metered, so there is one way to support and one way to bill. |
| Sender | **Shared.** One SMS sender ID or number and one WhatsApp Business sender for every school. Each message names the school in its text. |
| Pricing | **A price list per country/currency**, kept by the Super Admin. There is a price per SMS part and per WhatsApp message, with an optional per-school override. |
| Charging | **A monthly usage statement per school.** The Super Admin records the payment as an "Additional Service" in the existing payments. Sending never stops for non-payment. |

**This changes a project rule.** CLAUDE.md section 4 says there is no
billing beyond recording payments by hand. A usage statement is still not a
subscription:

- it has no plans or tiers;
- nothing renews automatically;
- it never switches anything off.

But metering and statements are new, so section 4 needs one line
recording this decision.

**Subaccounts are out.** A Twilio subaccount per school would have kept
usage apart, but a sender number belongs to a single account. With a
shared sender, every school sends through one account, and usage is
counted from our own message log, which already records every message.

## Outside the app, before launch

- **India (DLT).** Bulk SMS in India must go through a sender ID and
  message templates registered with the telecom regulator. School365ai
  registers its own entity, header and templates once, for the shared
  sender, and the app stores each template's ID against the SMS events.
  Until a template is registered, that event cannot go out by SMS in India.
- **WhatsApp.** School365ai's WhatsApp Business sender, and each template,
  must be approved by Meta through Twilio. The existing Message Templates
  mapping (a Content SID per event) moves from each school to the platform.

## The phases

| | Phase | What it does |
|---|---|---|
| M1 | Platform account | A Super Admin **Messaging** screen beside Mail Settings: account SID, auth token, SMS sender, WhatsApp sender, test send, all encrypted. The Twilio adapter reads these. The per-school key fields go; a school keeps only its on/off switches and alert choices. WhatsApp and DLT template mappings become platform-level. |
| M2 | Metering | Each message accepted by Twilio is priced when it is sent, and the price is kept on the message row: channel, SMS parts (GSM-7 160/153 per part, Unicode 70/67), unit price and the school's currency. Failed and skipped messages are never charged. Twilio's status callbacks, signature-checked, mark delivered or failed. |
| M3 | Price list | A Super Admin screen to set the price per SMS part and per WhatsApp message for each currency, with per-school overrides. A school's rate is copied onto each message, so a later price change never rewrites history. |
| M4 | Statements | A monthly statement per school: counts, parts and amount, in its own currency, as a PDF in the shared design. The Super Admin sees every school's usage and, from a statement, records the payment as an "Additional Service". A School Admin sees their own usage and this month so far. |
| M5 | Guard rails | Optional monthly caps per school with warnings at 80% and 100%. A cap only warns and never stops sending, matching "never stops for non-payment". |

## Answered 2026-10-29

- **M2:** a message is charged **only once Twilio reports it delivered**.
  Accepted, failed and undelivered messages cost the school nothing, so
  the delivery callbacks are what billing rests on.
- **M4:** each school's statement is **emailed automatically** when the
  month closes.
- **M5:** the Super Admin can set a limit per school, **per month or per
  year**. Reaching it warns and never stops sending.
