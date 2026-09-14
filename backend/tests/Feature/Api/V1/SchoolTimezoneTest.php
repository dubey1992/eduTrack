<?php

namespace Tests\Feature\Api\V1;

use App\Enums\LeaveStatus;
use App\Enums\MessageStatus;
use App\Enums\PaymentStatus;
use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Announcement;
use App\Models\ClassSection;
use App\Models\Driver;
use App\Models\Message;
use App\Models\Payment;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\User;
use App\Models\Vehicle;
use App\Support\SchoolClock;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

/**
 * Per-school timezones.
 *
 * Schools run in different countries, so the server's idea of "today" is
 * nobody's in particular. Every test here freezes a UTC instant on which the
 * server and the school genuinely disagree about the date, then checks that
 * the school's answer is the one that counts.
 *
 * Two instants do most of the work:
 *
 *   2026-09-16 19:00 UTC = 2026-09-17 00:30 in Asia/Kolkata (school ahead)
 *   2026-09-16 02:00 UTC = 2026-09-15 22:00 in America/New_York (behind)
 */
class SchoolTimezoneTest extends TestCase
{
    use RefreshDatabase;

    /** Half an hour into the 17th in Delhi; the server is still on the 16th. */
    private const string AHEAD = '2026-09-16 19:00:00';

    /** Late on the 15th in New York; the server has already reached the 16th. */
    private const string BEHIND = '2026-09-16 02:00:00';

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function freeze(string $utc): void
    {
        Carbon::setTestNow(Carbon::parse($utc, 'UTC'));
    }

    // -- the clock itself ------------------------------------------------

    public function test_a_schools_clock_reports_its_own_date(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);

        $this->assertSame('2026-09-17', $school->clock()->date());
        $this->assertSame('2026-09-16', SchoolClock::platform()->date());
    }

    public function test_a_school_day_maps_onto_a_utc_window(): void
    {
        $this->freeze(self::AHEAD);
        $clock = SchoolClock::for(School::factory()->create(['timezone' => 'Asia/Kolkata']));

        [$start, $end] = $clock->todayRange();

        // The 17th in Delhi began at 18:30 UTC on the 16th.
        $this->assertSame('2026-09-16 18:30:00', $start->utc()->format('Y-m-d H:i:s'));
        $this->assertSame('2026-09-17 18:30:00', $end->utc()->format('Y-m-d H:i:s'));
    }

    public function test_an_unusable_timezone_falls_back_to_utc_instead_of_throwing(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Mars/Olympus_Mons']);

        $this->assertSame('UTC', $school->clock()->timezone());
        $this->assertSame('2026-09-16', $school->clock()->date());
    }

    public function test_a_super_admin_with_no_school_reads_the_platform_clock(): void
    {
        $this->freeze(self::AHEAD);
        config(['app.platform_timezone' => 'Asia/Kolkata']);

        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->assertSame('Asia/Kolkata', SchoolClock::forUser($superAdmin)->timezone());
        $this->assertSame('2026-09-17', SchoolClock::forUser($superAdmin)->date());
    }

    public function test_a_scoped_listing_follows_the_school_a_super_admin_filtered_to(): void
    {
        $this->freeze(self::AHEAD);
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);

        $this->assertSame('2026-09-17', SchoolClock::forScope($superAdmin, $school->id)->date());
        $this->assertSame('2026-09-16', SchoolClock::forScope($superAdmin, null)->date());
    }

    // -- attendance ------------------------------------------------------

    /**
     * @return array{school: School, section: ClassSection, student: Student, teacher: User}
     */
    private function makeClass(string $timezone): array
    {
        $school = School::factory()->create(['name' => 'Sunrise Public School', 'timezone' => $timezone]);
        $year = AcademicYear::factory()->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = ClassSection::factory()
            ->forClass(SchoolClass::factory()->forAcademicYear($year)->create(['name' => 'Grade 8']))
            ->withClassTeacher($teacher)
            ->create(['name' => 'A']);

        return [
            'school' => $school,
            'section' => $section,
            'student' => Student::factory()->forSection($section)->create(),
            'teacher' => $teacher,
        ];
    }

    public function test_the_register_accepts_the_schools_today_while_the_server_is_still_on_yesterday(): void
    {
        Queue::fake();
        $this->freeze(self::AHEAD);
        $f = $this->makeClass('Asia/Kolkata');

        // It is already the 17th in Delhi. Measured against the server's UTC
        // date this looks like tomorrow, and used to be rejected as such.
        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $f['section']->id,
            'attendance_date' => '2026-09-17',
            'records' => [['student_id' => $f['student']->id, 'status' => 'present']],
        ])->assertCreated();

        $this->assertDatabaseHas('attendances', ['attendance_date' => '2026-09-17']);
    }

    public function test_the_register_still_refuses_a_date_that_is_future_at_the_school(): void
    {
        $this->freeze(self::AHEAD);
        $f = $this->makeClass('Asia/Kolkata');

        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $f['section']->id,
            'attendance_date' => '2026-09-18',
            'records' => [['student_id' => $f['student']->id, 'status' => 'present']],
        ])->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['attendance_date']]]);
    }

    public function test_a_school_behind_the_server_cannot_mark_the_servers_today(): void
    {
        $this->freeze(self::BEHIND);
        $f = $this->makeClass('America/New_York');

        // The server says the 16th; in New York it is still the 15th, so the
        // 16th has not happened there yet.
        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $f['section']->id,
            'attendance_date' => '2026-09-16',
            'records' => [['student_id' => $f['student']->id, 'status' => 'present']],
        ])->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['attendance_date']]]);
    }

    // -- announcements ---------------------------------------------------

    public function test_an_announcement_may_expire_on_the_schools_today(): void
    {
        Queue::fake();
        $this->freeze(self::BEHIND);
        $f = $this->makeClass('America/New_York');
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($f['school'])->create();

        // The 15th is today in New York, though the server has reached the
        // 16th and would call it a date already in the past.
        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/announcements', [
            'title' => 'Half day tomorrow',
            'body' => 'School closes at noon tomorrow for staff training.',
            'audience_type' => 'all_school',
            'channels' => 'sms_in_app',
            'expires_at' => '2026-09-15',
        ])->assertCreated();
    }

    public function test_an_announcement_is_still_showing_on_its_expiry_day_at_the_school(): void
    {
        $this->freeze(self::BEHIND);
        $school = School::factory()->create(['timezone' => 'America/New_York']);
        $announcement = Announcement::factory()->forSchool($school)->create(['expires_at' => '2026-09-15']);

        $this->assertFalse($announcement->fresh()->hasExpired());

        // The same notice at a school on UTC, where the 16th has arrived.
        $school->update(['timezone' => 'UTC']);
        $this->assertTrue($announcement->fresh()->hasExpired());
    }

    // -- the message log -------------------------------------------------

    public function test_todays_message_count_uses_the_schools_day_not_the_servers(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        // Inside the school's 17th, which began at 18:30 UTC on the 16th.
        Message::factory()->forSchool($school)->status(MessageStatus::Sent)
            ->create(['created_at' => Carbon::parse('2026-09-16 18:45:00', 'UTC')]);
        // Still the 16th in Delhi, so outside it - though it shares a UTC day
        // with the message above.
        Message::factory()->forSchool($school)->status(MessageStatus::Sent)
            ->create(['created_at' => Carbon::parse('2026-09-16 06:00:00', 'UTC')]);

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/communication/summary')
            ->assertOk()
            ->assertJsonPath('sent_today', 1);
    }

    public function test_the_log_renders_times_in_the_schools_timezone(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        Message::factory()->forSchool($school)->status(MessageStatus::Sent)->create([
            'created_at' => Carbon::parse('2026-09-16 18:45:00', 'UTC'),
            'sent_at' => Carbon::parse('2026-09-16 18:45:00', 'UTC'),
        ]);

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/communication/messages')
            ->assertOk()
            ->assertJsonPath('data.0.created_at_label', '12:15 AM')
            ->assertJsonPath('data.0.created_on_label', '09/17/2026')
            ->assertJsonPath('data.0.sent_at_label', '12:15 AM')
            ->assertJsonPath('data.0.timezone', 'Asia/Kolkata');
    }

    public function test_a_date_filter_means_days_at_the_school(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        Message::factory()->forSchool($school)->status(MessageStatus::Sent)
            ->create(['created_at' => Carbon::parse('2026-09-16 18:45:00', 'UTC')]);

        // Asking for the 17th finds it, because at the school it happened on
        // the 17th - even though its UTC date is the 16th.
        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/communication/messages?date_from=2026-09-17&date_to=2026-09-17')
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/communication/messages?date_from=2026-09-16&date_to=2026-09-16')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    // -- transport -------------------------------------------------------

    public function test_a_trip_is_dated_and_timed_at_the_school(): void
    {
        Queue::fake();
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);
        $vehicle = Vehicle::factory()->forSchool($school)->create(['name' => 'Bus 04']);
        $driver = Driver::factory()->forSchool($school)->create();
        $route = TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->withDriver($driver)->create();
        TransportStop::factory()->forRoute($route)->atSequence(1)->create();
        $manager = User::factory()->role(UserRole::TransportManager)->forSchool($school)->create();

        // Started at 00:30 on the 17th in Delhi, not 19:00 on the 16th.
        $this->actingAs($manager, 'sanctum')->postJson('/api/v1/transport/trips', [
            'route_id' => $route->id,
            'direction' => 'pickup',
        ])->assertCreated()
            ->assertJsonPath('trip_date', '2026-09-17')
            ->assertJsonPath('started_at_label', '12:30 AM')
            ->assertJsonPath('timezone', 'Asia/Kolkata');
    }

    // -- leave -----------------------------------------------------------

    public function test_on_leave_today_is_counted_on_the_schools_calendar(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $profile = StaffProfile::factory()->forUser($teacher)->create();

        // One day of leave, on the 17th - today in Delhi, tomorrow by the
        // server's reckoning.
        StaffLeave::factory()->forStaff($profile)->create([
            'start_date' => '2026-09-17',
            'end_date' => '2026-09-17',
            'status' => LeaveStatus::Approved,
        ]);

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/leaves/summary')
            ->assertOk()
            ->assertJsonPath('on_leave_today', 1);
    }

    // -- platform-level figures ------------------------------------------

    public function test_cross_school_collection_uses_the_platform_timezone(): void
    {
        $this->freeze('2026-09-30 20:00:00');
        config(['app.platform_timezone' => 'Asia/Kolkata']);

        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);

        // It is already 1 October on the platform's clock, so a payment dated
        // 1 October counts towards this month and a 30 September one does not.
        Payment::factory()->forSchool($school)->create([
            'payment_date' => '2026-10-01',
            'amount' => 5000,
            'currency_code' => 'INR',
            'status' => PaymentStatus::Paid,
        ]);
        Payment::factory()->forSchool($school)->create([
            'payment_date' => '2026-09-30',
            'amount' => 900,
            'currency_code' => 'INR',
            'status' => PaymentStatus::Paid,
        ]);

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/payments/summary')->assertOk();

        $monthly = collect($response->json('monthly_by_currency'))->firstWhere('currency_code', 'INR');
        $this->assertSame('5000.00', (string) $monthly['total']);
    }

    // -- setting and reading the zone ------------------------------------

    public function test_a_school_cannot_be_created_with_an_unknown_timezone(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/schools', [
            'name' => 'Sunrise Public School',
            'email' => 'hello@sunrise.test',
            'phone' => '+91 98765 43210',
            'address' => '12 School Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'country' => 'India',
            'postal_code' => '110001',
            'currency_code' => 'INR',
            'timezone' => 'Mars/Olympus_Mons',
        ])->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['timezone']]]);
    }

    public function test_a_super_admin_can_change_a_schools_timezone(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create(['timezone' => 'UTC']);

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/schools/{$school->id}", ['timezone' => 'Africa/Lagos'])
            ->assertOk()
            ->assertJsonPath('timezone', 'Africa/Lagos');

        $this->assertSame('Africa/Lagos', $school->fresh()->timezone);
    }

    public function test_the_session_carries_the_schools_clock(): void
    {
        $this->freeze(self::AHEAD);
        $school = School::factory()->create(['timezone' => 'Asia/Kolkata']);
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('timezone', 'Asia/Kolkata')
            ->assertJsonPath('current_time', '2026-09-17T00:30:00+05:30');
    }

    public function test_the_timezone_list_is_available_to_a_signed_in_user_only(): void
    {
        $this->getJson('/api/v1/timezones')->assertUnauthorized();

        $admin = User::factory()->role(UserRole::SchoolAdmin)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/timezones?q=kolkata')->assertOk();

        $this->assertSame('Asia/Kolkata', $response->json('data.0.name'));
        $this->assertSame('Asia/Kolkata (GMT+05:30)', $response->json('data.0.label'));
    }
}
