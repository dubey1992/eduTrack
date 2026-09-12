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
the log are both rendered server-side in `APP_TIMEZONE`, so they always agree.
Set it to the school's own timezone at deployment.

This is a single timezone per deployment. A future phase should give each
school its own, because the product is explicitly multi-nation: two schools in
different countries on one deployment would share this setting today.

## Adding a real provider

1. Write an adapter implementing `App\Support\Sms\SmsGateway`.
2. Register it in `config/communication.php` under `gateways`, with a `driver`
   key and a human-readable `label`.
3. Teach `SmsGatewayManager::gateway()` to build it.

Schools then pick it in their Alert Settings. Nothing outside
`App\Support\Sms` needs to change, and push notifications arrive the same way
later without a schema change.
