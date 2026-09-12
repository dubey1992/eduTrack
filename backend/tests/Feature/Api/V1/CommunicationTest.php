<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AttendanceAlertMode;
use App\Enums\MessageCategory;
use App\Enums\MessageChannel;
use App\Enums\MessageEvent;
use App\Enums\MessageStatus;
use App\Enums\UserRole;
use App\Jobs\SendMessageJob;
use App\Models\CommunicationSetting;
use App\Models\Message;
use App\Models\MessageTemplate;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

/**
 * The Communication Center: the message log and its KPIs, the template
 * manager, the alert switches and each user's own inbox.
 */
class CommunicationTest extends TestCase
{
    use RefreshDatabase;

    private const string MESSAGES = '/api/v1/communication/messages';

    private const string TEMPLATES = '/api/v1/communication/templates';

    private const string SETTINGS = '/api/v1/communication/settings';

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-09-16 09:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /**
     * @return array{school: School, admin: User, teacher: User, staff: User, superAdmin: User}
     */
    private function makeSchool(): array
    {
        $school = School::factory()->create();

        return [
            'school' => $school,
            'admin' => User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(),
            'teacher' => User::factory()->role(UserRole::Teacher)->forSchool($school)->create(),
            'staff' => User::factory()->role(UserRole::Staff)->forSchool($school)->create(),
            'superAdmin' => User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]),
        ];
    }

    // -- the log ---------------------------------------------------------

    public function test_a_school_admin_sees_their_schools_message_log_newest_first(): void
    {
        $f = $this->makeSchool();
        Message::factory()->forSchool($f['school'])->create([
            'recipient_name' => 'Raj Kumar',
            'created_at' => '2026-09-16 08:42:00',
        ]);
        Message::factory()->forSchool($f['school'])->forEvent(MessageEvent::TransportBoarded)->create([
            'recipient_name' => 'Neha Mehta',
            'created_at' => '2026-09-16 07:42:00',
        ]);

        $response = $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES);

        $response->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.recipient_name', 'Raj Kumar')
            ->assertJsonPath('data.0.category', 'attendance')
            ->assertJsonPath('data.0.channel_label', 'SMS')
            ->assertJsonPath('data.1.recipient_name', 'Neha Mehta')
            ->assertJsonPath('data.1.category_label', 'Transport')
            ->assertJsonStructure([
                'data' => [['id', 'event_label', 'body', 'status', 'status_label', 'sent_at']],
                'meta' => ['current_page', 'total'],
            ]);
    }

    public function test_the_log_never_leaks_another_schools_messages(): void
    {
        $f = $this->makeSchool();
        $other = School::factory()->create();
        $theirs = Message::factory()->forSchool($other)->create();
        Message::factory()->forSchool($f['school'])->create();

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES)
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES.'/'.$theirs->id)->assertForbidden();
    }

    public function test_a_super_admin_sees_every_school_and_can_narrow_to_one(): void
    {
        $f = $this->makeSchool();
        $other = School::factory()->create();
        Message::factory()->forSchool($f['school'])->create();
        Message::factory()->forSchool($other)->create();

        $this->actingAs($f['superAdmin'], 'sanctum')->getJson(self::MESSAGES)
            ->assertOk()
            ->assertJsonCount(2, 'data');

        $this->actingAs($f['superAdmin'], 'sanctum')->getJson(self::MESSAGES.'?school_id='.$other->id)
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.school_id', $other->id);
    }

    public function test_teachers_and_staff_cannot_read_the_log_at_all(): void
    {
        $f = $this->makeSchool();
        $message = Message::factory()->forSchool($f['school'])->create();

        foreach (['teacher', 'staff'] as $role) {
            $this->actingAs($f[$role], 'sanctum')->getJson(self::MESSAGES)->assertForbidden();
            $this->actingAs($f[$role], 'sanctum')->getJson(self::MESSAGES.'/'.$message->id)->assertForbidden();
        }
    }

    public function test_the_log_and_the_inbox_both_need_a_signed_in_user(): void
    {
        $this->getJson(self::MESSAGES)->assertUnauthorized();
        $this->getJson(self::TEMPLATES)->assertUnauthorized();
        $this->getJson('/api/v1/inbox')->assertUnauthorized();
    }

    public function test_the_log_renders_its_times_server_side_so_they_match_the_message_text(): void
    {
        $f = $this->makeSchool();
        Message::factory()->forSchool($f['school'])->create([
            'created_at' => '2026-09-16 08:42:00',
            'sent_at' => '2026-09-16 08:42:10',
        ]);

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES)
            ->assertOk()
            ->assertJsonPath('data.0.created_at_label', '8:42 AM')
            ->assertJsonPath('data.0.created_on_label', '16 Sep 2026')
            ->assertJsonPath('data.0.sent_at_label', '8:42 AM');
    }

    public function test_an_api_call_without_an_accept_header_is_still_a_clean_401(): void
    {
        // A bare curl must not blow up trying to redirect a guest to a web
        // login page that this API does not have.
        $response = $this->get(self::MESSAGES, ['Accept' => 'text/html']);

        $response->assertUnauthorized()->assertJsonPath('code', 'UNAUTHENTICATED');
        $this->assertStringNotContainsString('Route [login] not defined', $response->getContent());
    }

    public function test_the_log_filters_by_category_status_channel_and_search_term(): void
    {
        $f = $this->makeSchool();
        Message::factory()->forSchool($f['school'])->create([
            'recipient_name' => 'Raj Kumar',
            'student_name' => 'Arjun Kumar',
            'body' => 'Arjun Kumar was marked ABSENT today.',
        ]);
        Message::factory()->forSchool($f['school'])->forEvent(MessageEvent::TransportBoarded)
            ->status(MessageStatus::Failed)->create([
                'recipient_name' => 'Neha Mehta',
                'student_name' => 'Aarav Mehta',
                'body' => 'Aarav Mehta boarded Bus 04.',
            ]);
        Message::factory()->forSchool($f['school'])->forEvent(MessageEvent::LeaveApproved)
            ->create([
                'channel' => MessageChannel::InApp,
                'recipient_mobile' => null,
                'student_name' => null,
                'body' => 'Your casual leave was approved.',
            ]);

        $admin = $this->actingAs($f['admin'], 'sanctum');

        $admin->getJson(self::MESSAGES.'?category=transport')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.recipient_name', 'Neha Mehta');
        $admin->getJson(self::MESSAGES.'?status=failed')->assertOk()->assertJsonCount(1, 'data');
        $admin->getJson(self::MESSAGES.'?channel=in_app')->assertOk()->assertJsonCount(1, 'data');
        $admin->getJson(self::MESSAGES.'?q=Arjun')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.student_name', 'Arjun Kumar');
        $admin->getJson(self::MESSAGES.'?q=nobody')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_the_log_filters_by_date_range_and_rejects_a_backwards_one(): void
    {
        $f = $this->makeSchool();
        Message::factory()->forSchool($f['school'])->create(['created_at' => '2026-09-10 08:00:00']);
        Message::factory()->forSchool($f['school'])->create(['created_at' => '2026-09-16 08:00:00']);

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES.'?date_from=2026-09-15')
            ->assertOk()->assertJsonCount(1, 'data');

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES.'?date_from=2026-09-16&date_to=2026-09-10')
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['date_to']]]);
    }

    public function test_the_summary_counts_todays_traffic_and_the_delivery_rate(): void
    {
        $f = $this->makeSchool();
        Message::factory()->count(3)->forSchool($f['school'])->status(MessageStatus::Sent)->create();
        Message::factory()->forSchool($f['school'])->status(MessageStatus::Failed)->create();
        Message::factory()->forSchool($f['school'])->status(MessageStatus::Skipped)->create();
        Message::factory()->forSchool($f['school'])->status(MessageStatus::Sent)->create(['created_at' => '2026-09-01 08:00:00']);

        $this->actingAs($f['admin'], 'sanctum')->getJson('/api/v1/communication/summary')
            ->assertOk()
            ->assertJsonPath('sent_today', 3)
            ->assertJsonPath('failed_today', 1)
            ->assertJsonPath('skipped_today', 1)
            ->assertJsonPath('total', 6);

        $this->assertEquals(75.0, $this->actingAs($f['admin'], 'sanctum')
            ->getJson('/api/v1/communication/summary')->json('delivery_rate'));
    }

    public function test_the_sms_tile_does_not_count_in_app_copies(): void
    {
        $f = $this->makeSchool();
        Message::factory()->count(2)->forSchool($f['school'])->status(MessageStatus::Sent)->create();
        Message::factory()->inboxFor($f['teacher'])->status(MessageStatus::Sent)->create();

        $this->actingAs($f['admin'], 'sanctum')->getJson('/api/v1/communication/summary')
            ->assertOk()
            ->assertJsonPath('sent_today', 3)
            ->assertJsonPath('sms_sent_today', 2);
    }

    public function test_the_log_reports_the_gateways_name_not_its_config_key(): void
    {
        $f = $this->makeSchool();
        Message::factory()->forSchool($f['school'])->create(['provider' => 'log']);

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::MESSAGES)
            ->assertOk()
            ->assertJsonPath('data.0.provider', 'log')
            ->assertJsonPath('data.0.provider_label', 'Demo Gateway');
    }

    public function test_an_unknown_template_event_is_a_not_found_whatever_the_body_says(): void
    {
        $f = $this->makeSchool();

        // Short body: the missing event must still win over body validation.
        $this->actingAs($f['admin'], 'sanctum')->putJson(self::TEMPLATES.'/fees.overdue', ['body' => 'short'])
            ->assertNotFound();

        $this->actingAs($f['admin'], 'sanctum')->deleteJson(self::TEMPLATES.'/fees.overdue')
            ->assertNotFound();
    }

    public function test_the_delivery_rate_is_null_when_nothing_was_attempted_today(): void
    {
        $f = $this->makeSchool();
        Message::factory()->forSchool($f['school'])->status(MessageStatus::Skipped)->create();

        $this->actingAs($f['admin'], 'sanctum')->getJson('/api/v1/communication/summary')
            ->assertOk()
            ->assertJsonPath('delivery_rate', null)
            ->assertJsonPath('sent_today', 0);
    }

    // -- retry -----------------------------------------------------------

    public function test_a_failed_message_can_be_sent_again(): void
    {
        Queue::fake();
        $f = $this->makeSchool();
        $message = Message::factory()->forSchool($f['school'])->status(MessageStatus::Failed)->create();

        $this->actingAs($f['admin'], 'sanctum')->postJson(self::MESSAGES.'/'.$message->id.'/retry')
            ->assertOk()
            ->assertJsonPath('status', 'queued')
            ->assertJsonPath('failure_reason', null);

        Queue::assertPushed(SendMessageJob::class);
    }

    public function test_a_delivered_or_skipped_message_cannot_be_sent_again(): void
    {
        $f = $this->makeSchool();
        $sent = Message::factory()->forSchool($f['school'])->status(MessageStatus::Sent)->create();
        $skipped = Message::factory()->forSchool($f['school'])->status(MessageStatus::Skipped)->create();

        foreach ([$sent, $skipped] as $message) {
            $this->actingAs($f['admin'], 'sanctum')->postJson(self::MESSAGES.'/'.$message->id.'/retry')
                ->assertStatus(409)
                ->assertJsonPath('code', 'MESSAGE_NOT_RETRYABLE');
        }
    }

    public function test_only_admins_of_the_owning_school_can_retry(): void
    {
        $f = $this->makeSchool();
        $message = Message::factory()->forSchool($f['school'])->status(MessageStatus::Failed)->create();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($f['teacher'], 'sanctum')->postJson(self::MESSAGES.'/'.$message->id.'/retry')->assertForbidden();
        $this->actingAs($otherAdmin, 'sanctum')->postJson(self::MESSAGES.'/'.$message->id.'/retry')->assertForbidden();
        $this->assertSame(MessageStatus::Failed, $message->refresh()->status);
    }

    // -- templates -------------------------------------------------------

    public function test_the_template_list_shows_every_event_with_its_shipped_wording(): void
    {
        $f = $this->makeSchool();

        $response = $this->actingAs($f['admin'], 'sanctum')->getJson(self::TEMPLATES);

        $response->assertOk()->assertJsonCount(count(MessageEvent::cases()));
        $absent = collect($response->json())->firstWhere('event', 'attendance.absent');
        $this->assertSame(MessageEvent::AttendanceAbsent->defaultBody(), $absent['body']);
        $this->assertFalse($absent['is_custom']);
        $this->assertContains('student_name', $absent['tokens']);
        $this->assertSame(['sms'], $absent['channels']);
    }

    public function test_a_school_can_reword_an_event_and_then_put_it_back(): void
    {
        $f = $this->makeSchool();
        $reworded = 'Hi {guardian_name}, {student_name} missed school on {date}.';

        $this->actingAs($f['admin'], 'sanctum')
            ->putJson(self::TEMPLATES.'/attendance.absent', ['body' => $reworded])
            ->assertOk()
            ->assertJsonPath('is_custom', true)
            ->assertJsonPath('body', $reworded)
            ->assertJsonPath('updated_by_name', $f['admin']->name);

        $this->assertDatabaseHas('message_templates', [
            'school_id' => $f['school']->id,
            'event' => 'attendance.absent',
        ]);

        $this->actingAs($f['admin'], 'sanctum')->deleteJson(self::TEMPLATES.'/attendance.absent')
            ->assertOk()
            ->assertJsonPath('is_custom', false)
            ->assertJsonPath('body', MessageEvent::AttendanceAbsent->defaultBody());

        $this->assertDatabaseCount('message_templates', 0);
    }

    public function test_a_template_cannot_use_a_placeholder_the_event_does_not_provide(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')
            ->putJson(self::TEMPLATES.'/attendance.absent', ['body' => '{student_name} owes {fee_amount} rupees.'])
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['body']]]);

        $this->assertDatabaseCount('message_templates', 0);
    }

    public function test_a_template_body_must_be_present_and_within_the_length_limit(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')->putJson(self::TEMPLATES.'/attendance.absent', ['body' => ''])
            ->assertStatus(422);

        $this->actingAs($f['admin'], 'sanctum')
            ->putJson(self::TEMPLATES.'/attendance.absent', ['body' => str_repeat('a', 481)])
            ->assertStatus(422);
    }

    public function test_an_unknown_event_is_a_not_found(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')
            ->putJson(self::TEMPLATES.'/fees.overdue', ['body' => 'Anything at all here.'])
            ->assertNotFound();
    }

    public function test_only_admins_can_read_or_change_templates(): void
    {
        $f = $this->makeSchool();

        foreach (['teacher', 'staff'] as $role) {
            $this->actingAs($f[$role], 'sanctum')->getJson(self::TEMPLATES)->assertForbidden();
            $this->actingAs($f[$role], 'sanctum')
                ->putJson(self::TEMPLATES.'/attendance.absent', ['body' => 'Reworded by someone who may not.'])
                ->assertForbidden();
        }
    }

    public function test_an_admin_cannot_touch_another_schools_templates(): void
    {
        $f = $this->makeSchool();
        $other = School::factory()->create();

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::TEMPLATES.'?school_id='.$other->id)->assertForbidden();
        $this->actingAs($f['admin'], 'sanctum')
            ->putJson(self::TEMPLATES.'/attendance.absent', [
                'school_id' => $other->id,
                'body' => 'Not your school, {student_name}.',
            ])
            ->assertForbidden();
    }

    // -- settings --------------------------------------------------------

    public function test_a_school_that_never_saved_settings_gets_the_defaults(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::SETTINGS)
            ->assertOk()
            ->assertJsonPath('sms_enabled', true)
            ->assertJsonPath('attendance_alerts', 'absent')
            ->assertJsonPath('attendance_alerts_label', 'Absent only')
            ->assertJsonPath('provider', 'log')
            ->assertJsonPath('provider_label', 'Demo Gateway')
            ->assertJsonPath('is_saved', false);

        $this->assertDatabaseCount('communication_settings', 0);
    }

    public function test_an_admin_can_change_the_alert_switches(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')->putJson(self::SETTINGS, [
            'sms_enabled' => true,
            'attendance_alerts' => 'both',
            'transport_alerts_enabled' => false,
            'leave_alerts_enabled' => true,
            'provider' => 'log',
            'sender_id' => 'SUNRIS',
        ])
            ->assertOk()
            ->assertJsonPath('attendance_alerts', 'both')
            ->assertJsonPath('attendance_alerts_label', 'Present + Absent')
            ->assertJsonPath('transport_alerts_enabled', false)
            ->assertJsonPath('sender_id', 'SUNRIS')
            ->assertJsonPath('is_saved', true);

        $this->assertDatabaseHas('communication_settings', [
            'school_id' => $f['school']->id,
            'attendance_alerts' => 'both',
            'transport_alerts_enabled' => false,
        ]);
    }

    public function test_settings_reject_an_unavailable_gateway_a_bad_sender_id_and_a_bad_mode(): void
    {
        $f = $this->makeSchool();
        $valid = [
            'sms_enabled' => true,
            'attendance_alerts' => 'absent',
            'transport_alerts_enabled' => true,
            'leave_alerts_enabled' => true,
            'provider' => 'log',
        ];

        $this->actingAs($f['admin'], 'sanctum')->putJson(self::SETTINGS, [...$valid, 'provider' => 'twilio'])
            ->assertStatus(422)->assertJsonStructure(['details' => ['errors' => ['provider']]]);

        $this->actingAs($f['admin'], 'sanctum')->putJson(self::SETTINGS, [...$valid, 'sender_id' => 'not valid!'])
            ->assertStatus(422)->assertJsonStructure(['details' => ['errors' => ['sender_id']]]);

        $this->actingAs($f['admin'], 'sanctum')->putJson(self::SETTINGS, [...$valid, 'attendance_alerts' => 'sometimes'])
            ->assertStatus(422)->assertJsonStructure(['details' => ['errors' => ['attendance_alerts']]]);
    }

    public function test_only_admins_of_the_school_can_read_or_change_settings(): void
    {
        $f = $this->makeSchool();
        CommunicationSetting::factory()->forSchool($f['school'])->create();

        foreach (['teacher', 'staff'] as $role) {
            $this->actingAs($f[$role], 'sanctum')->getJson(self::SETTINGS)->assertForbidden();
        }

        $other = School::factory()->create();
        $this->actingAs($f['admin'], 'sanctum')->getJson(self::SETTINGS.'?school_id='.$other->id)->assertForbidden();
        $this->actingAs($f['admin'], 'sanctum')->putJson(self::SETTINGS, [
            'school_id' => $other->id,
            'sms_enabled' => false,
            'attendance_alerts' => 'off',
            'transport_alerts_enabled' => false,
            'leave_alerts_enabled' => false,
            'provider' => 'log',
        ])->assertForbidden();
    }

    public function test_a_super_admin_configures_one_school_at_a_time(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['superAdmin'], 'sanctum')->getJson(self::SETTINGS.'?school_id='.$f['school']->id)
            ->assertOk()
            ->assertJsonPath('school_id', $f['school']->id);

        $this->actingAs($f['superAdmin'], 'sanctum')->putJson(self::SETTINGS, [
            'school_id' => $f['school']->id,
            'sms_enabled' => false,
            'attendance_alerts' => 'off',
            'transport_alerts_enabled' => true,
            'leave_alerts_enabled' => true,
            'provider' => 'log',
        ])->assertOk()->assertJsonPath('sms_enabled', false);
    }

    // -- inbox -----------------------------------------------------------

    public function test_a_user_sees_only_their_own_in_app_messages(): void
    {
        $f = $this->makeSchool();
        Message::factory()->inboxFor($f['teacher'])->create(['body' => 'Your casual leave was approved.']);
        Message::factory()->inboxFor($f['staff'])->create();
        Message::factory()->forSchool($f['school'])->create();

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.body', 'Your casual leave was approved.');
    }

    public function test_the_unread_count_and_marking_read_keep_step(): void
    {
        $f = $this->makeSchool();
        $first = Message::factory()->inboxFor($f['teacher'])->create();
        Message::factory()->inboxFor($f['teacher'])->create();

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox/unread-count')
            ->assertOk()->assertJsonPath('unread', 2);

        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/inbox/'.$first->id.'/read')->assertOk();
        $this->assertNotNull($first->refresh()->read_at);

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox?unread=1')
            ->assertOk()->assertJsonCount(1, 'data');

        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/inbox/read-all')
            ->assertOk()->assertJsonPath('marked', 1);

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox/unread-count')
            ->assertOk()->assertJsonPath('unread', 0);
    }

    public function test_a_user_cannot_mark_someone_elses_message_read(): void
    {
        $f = $this->makeSchool();
        $theirs = Message::factory()->inboxFor($f['staff'])->create();

        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/inbox/'.$theirs->id.'/read')->assertForbidden();
        $this->assertNull($theirs->refresh()->read_at);
    }

    public function test_a_skipped_message_never_reaches_an_inbox(): void
    {
        $f = $this->makeSchool();
        Message::factory()->inboxFor($f['teacher'])->status(MessageStatus::Skipped)->create();

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()->assertJsonCount(0, 'data');
    }

    // -- template resolution ---------------------------------------------

    public function test_an_inactive_override_falls_back_to_the_shipped_wording(): void
    {
        $f = $this->makeSchool();
        MessageTemplate::factory()->forSchool($f['school'])->forEvent(MessageEvent::AttendanceAbsent)
            ->create(['body' => 'Custom but switched off.', 'is_active' => false]);

        $response = $this->actingAs($f['admin'], 'sanctum')->getJson(self::TEMPLATES);

        $absent = collect($response->json())->firstWhere('event', 'attendance.absent');
        $this->assertSame(MessageEvent::AttendanceAbsent->defaultBody(), $absent['body']);
        $this->assertFalse($absent['is_custom']);
    }

    public function test_every_event_reports_a_category_a_channel_and_a_body(): void
    {
        foreach (MessageEvent::cases() as $event) {
            $this->assertInstanceOf(MessageCategory::class, $event->category());
            $this->assertNotEmpty($event->channels());
            $this->assertNotEmpty($event->defaultBody());
        }

        $this->assertSame(
            [MessageChannel::InApp, MessageChannel::Sms],
            MessageEvent::LeaveApproved->channels(),
        );
        $this->assertSame(AttendanceAlertMode::PresentAndAbsent, AttendanceAlertMode::from('both'));
    }
}
