# Communication (Phase 16)

How eduTrack sends messages, and what an operator has to set up.

## The pipeline

Modules never talk to a gateway. They describe what happened:

```php
$notifications->notifyGuardian(MessageEvent::AttendanceAbsent, $student, [
    'class_name' => 'Grade 8 A',
    'date' => '16 Sep 2026',
], $actor);
```

`NotificationService` then resolves the school's wording, renders the
placeholders, writes a row to `messages`, and queues `SendMessageJob` after the
caller's transaction commits. No user action ever waits on a gateway.

## Message status, and what each one means

| Status | Meaning |
|---|---|
| `queued` | Written and waiting for the worker. |
| `sent` | The gateway accepted it. |
| `failed` | The gateway rejected it, or the job died. An admin can send it again. |
| `skipped` | The school wanted to send it but there was no mobile number on record. |

An alert a school has **switched off** is not recorded at all. Recording one row
per present student per day would bury the log, and the school never asked for
those messages. Only a message the school wanted but could not deliver is worth
a `skipped` row.

## Templates

Default wording lives on the `MessageEvent` enum, so every school starts with
sensible text and no seeding is needed. A `message_templates` row exists only
when a school rewords an event. The placeholders a template may use come from
the event itself, so a reworded template can never reference data the sender
does not have.

## Running the queue on cPanel

Shared hosting has no long-running worker, so the deployment runs the queue from
cron. Once a minute is usually enough:

```
* * * * * cd /home/<account>/edutrack/backend && php artisan queue:work --stop-when-empty --max-time=50 >> storage/logs/queue.log 2>&1
```

`--stop-when-empty` makes the worker exit once the batch is drained, so the
cron job never overlaps with itself. If the host forbids even that, set
`QUEUE_CONNECTION=sync` and messages are sent inline; the request is slower but
nothing is lost.

## Timezones

Times written into messages ("Aarav boarded at 7:42 AM") and the times shown in
the log are both rendered server-side in **the school's own timezone**, so they
always agree with each other and with the clock on the wall wherever the school
is. Two schools in different countries on one deployment each get their own.

The zone is `schools.timezone`, and everything reads it through
`App\Support\SchoolClock`. "SMS sent today" counts the school's day, not the
server's - which begins at a different instant for every zone.

See [timezones.md](timezones.md) for the full rule and what to do when you add
a feature that touches a date.

## Channels (added 2026-09-19, Python backend only)

Decided with the user after Phase 21 and built on the Python backend only,
like Phases 19 to 21. Laravel still owns the schema, so the six schema
changes are Laravel migrations dated `2026_09_27`.

```
FEATURE: SMS, WhatsApp and email as channels; messages written by hand; SMTP set in the app
DATABASE: students + guardian_email, student_mobile, student_email
          communication_settings + whatsapp_enabled, whatsapp_provider, email_enabled, credentials (encrypted)
          messages + recipient_email, template_parameters
          whatsapp_templates, mail_settings (new); announcements.channels widened to 60
API: PUT communication/settings (+channels, credentials), POST communication/settings/test,
     PUT/DELETE communication/templates/{event}/whatsapp,
     POST communication/notices, GET communication/notices/preview,
     GET/PUT settings/mail, POST settings/mail/test
```

### A message reaches a person on every channel that is on

Each school switches SMS, WhatsApp and email on or off in its Alert
Settings. When an alert or a notice goes out, the pipeline in
`school/notifications.py` records one copy per channel:

| The channel is | The person has an address | Recorded as |
|---|---|---|
| off | (any) | nothing - the same rule as a switched-off alert |
| on | yes | `queued`, and the worker sends it |
| on | no | `skipped`, with "No mobile number on record." or "No email address on record." |
| WhatsApp, on | yes, but the event has no template mapped | `skipped`, "No WhatsApp template is mapped for this message." |

The in-app inbox is always on and costs nothing, but it belongs to a login:
guardians and students have none, so they never get an inbox copy and are
never "skipped" for one.

Who has which address: a guardian is reached on `guardian_mobile` and
`guardian_email`; a student directly on `student_mobile` and `student_email`
(all three are new and optional); staff on their account's mobile and email.

### Providers, and where their keys live

Each school signs its own contract with a provider, so the credentials
live on the school's settings row, not on the server. The API takes them as
`credentials: {twilio: {...}, meta: {...}}`; a field left out is kept, a
blank one cleared, and **no value ever comes back** - the answer says which
fields are set, with the last four characters of a non-secret one so an
administrator can tell which account is on file.

| Provider | Carries | Fields |
|---|---|---|
| Demo Gateway (`log`) | SMS, WhatsApp | none - records the message and delivers nothing, and the screen says so |
| Twilio | SMS, WhatsApp | account SID, auth token, SMS sender number, WhatsApp sender number |
| Meta WhatsApp Cloud API | WhatsApp | phone number ID, access token |

Adapters live in `school/gateways/`. Each one talks to its provider at the
HTTP boundary (`gateways/http.py`, standard-library urllib) and never
raises: a refusal or an outage is a `failed` row with the provider's own
reason, so the worker moves on to the next message.

`POST communication/settings/test` sends one message through the school's
own account right away, so an administrator finds out whether the account
works before a parent does. It writes nothing to the log.

**At rest, the column is ciphertext.** `school/crypto.py` encrypts the JSON
with Fernet under `DJANGO_ENCRYPTION_KEY` - its own key, not `SECRET_KEY`,
so the two rotate independently. Development and the tests derive a key
from the throwaway secret; a real deployment must set one, or the server
refuses to start. The audit trail drops `credentials` and every
`*_token` field, even as ciphertext.

### WhatsApp only carries templates

WhatsApp business messaging refuses free text unless the recipient wrote
first within the last day. So every message the school starts is a template
the provider approved beforehand, and a school maps each event to one of its
templates in the Message Templates dialog: the template's name (a Content
SID on Twilio, a name on Meta), its language, and which of the event's
tokens fill its numbered parameters, in order. The values are filled in when
the message is recorded and kept on the row (`template_parameters`), so the
worker never rebuilds them from data that has changed since.

An event with no mapping is skipped on WhatsApp with that as the reason;
the SMS and email copies go out regardless.

### Messages written by hand

`POST communication/notices` is the Communication Center's Send Message
dialog. There is no row for a notice - only the messages it becomes, plus
one `notice.sent` entry in the audit trail saying who sent what to whom.

| Kind | Event | Needs |
|---|---|---|
| message | `general.message` | subject, body |
| emergency | `emergency.alert` | body; goes to everyone by default and on every channel that is on |
| fee_reminder | `fee.reminder` | amount and due date; rendered in the school's currency and date format. There is still no fee module - this is a reminder, not a ledger |

Audiences: one student, one staff member, a class section, a department,
all parents, all students, all teachers, all staff, everyone. For an
audience made of students the form also says who receives it: their
guardians (default), the students themselves, or both.

One person is told in the request (201, with the message rows). A group is
handed to the queue (202) and fanned out by the worker, so a whole-school
emergency never holds the request open. The preview endpoint counts who
would be reached, per channel, before anything is written. A channel the
school has switched off is refused by name rather than silently carrying
nothing, and an audience nobody in can be reached is refused rather than
recorded as sent to nobody.

Announcements can now go out on any mix of the four channels: `channels`
takes the three original names or a comma-separated list such as
`in_app,sms,whatsapp`.

### Where email leaves from

Every email - password resets, receipts, payslips, the email channel -
goes through `school/mailer.py`, which answers one question: the SMTP
settings the Super Admin saved in the app (`settings/mail`, one row for the
platform, password encrypted and never returned), or the `MAIL_*`
environment when there are none or the row is switched off. The
environment is what a fresh deployment sends through before anybody has
opened the Email Settings screen. `POST settings/mail/test` sends one email
through the saved settings and keeps the outcome on the row, so the screen
shows the last result beside the settings.

## Adding a provider

Write an adapter in `school/gateways/` with `name`, `label`, `delivers`,
`CREDENTIALS` and `send(...)` (SMS) or `send_template(...)` (WhatsApp), and
register it in `school/sms.py` or `school/whatsapp.py`. Schools then pick it
in their Alert Settings, and the settings screen draws its credential fields
from `CREDENTIALS` without knowing the provider. Nothing outside
`school/gateways` changes.

The Laravel side keeps its original `App\Support\Sms\SmsGateway` shape and
the log gateway only; it is frozen.
