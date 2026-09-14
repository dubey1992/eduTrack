<?php

namespace Tests\Feature\Api\V1;

use App\Enums\StaffAttendanceStatus;
use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Driver;
use App\Models\Holiday;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffAttendance;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\TimetableEntry;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

/**
 * What a holiday actually stops, and what it leaves alone.
 *
 * Six modules consult the calendar and the rest ignore it, which is
 * deliberate but easy to forget. These pin the whole matrix in one place so a
 * later change cannot quietly widen or narrow it.
 *
 * Attendance can only be recorded for a day that has happened and leave can
 * only be booked for one that has not, so the fixture carries a holiday on
 * each side of today.
 */
class HolidayRestrictionsTest extends TestCase
{
    use RefreshDatabase;

    /** Monday 7 September - a past holiday, for anything already recorded. */
    private const string PAST_HOLIDAY = '2026-09-07';

    /** Monday 21 September - a future holiday, for anything being booked. */
    private const string FUTURE_HOLIDAY = '2026-09-21';

    /** The Saturday before the past holiday; never a working day. */
    private const string SATURDAY = '2026-09-05';

    /** Tuesday 8 September - an ordinary working day. */
    private const string WORKING_DAY = '2026-09-08';

    protected function setUp(): void
    {
        parent::setUp();
        // Midday on Monday 14 September, so the dates above sit either side.
        Carbon::setTestNow(Carbon::parse('2026-09-14 12:00:00', 'UTC'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /**
     * @return array<string, mixed>
     */
    private function makeSchool(): array
    {
        $school = School::factory()->create(['name' => 'Sunrise Public School']);

        Holiday::factory()->forSchool($school)->create([
            'name' => 'Founders Day',
            'start_date' => self::PAST_HOLIDAY,
            'end_date' => self::PAST_HOLIDAY,
        ]);
        Holiday::factory()->forSchool($school)->create([
            'name' => 'Harvest Break',
            'start_date' => self::FUTURE_HOLIDAY,
            'end_date' => self::FUTURE_HOLIDAY,
        ]);

        $year = AcademicYear::factory()->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = ClassSection::factory()
            ->forClass(SchoolClass::factory()->forAcademicYear($year)->create(['name' => 'Grade 8']))
            ->withClassTeacher($teacher)
            ->create(['name' => 'A']);

        return [
            'school' => $school,
            'section' => $section,
            'teacher' => $teacher,
            'student' => Student::factory()->forSection($section)->create(),
            'admin' => User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(),
        ];
    }

    /**
     * @param  array<string, mixed>  $f
     */
    private function submitAttendance(array $f, string $date)
    {
        return $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $f['section']->id,
            'attendance_date' => $date,
            'records' => [['student_id' => $f['student']->id, 'status' => 'present']],
        ]);
    }

    // -- what a holiday stops --------------------------------------------

    public function test_student_attendance_cannot_be_marked_on_a_holiday(): void
    {
        Queue::fake();
        $f = $this->makeSchool();

        $this->submitAttendance($f, self::PAST_HOLIDAY)
            ->assertStatus(409)
            ->assertJsonPath('code', 'ATTENDANCE_ON_HOLIDAY')
            ->assertJsonPath('message', 'Attendance cannot be marked on Founders Day - it is a holiday.');
    }

    public function test_staff_attendance_cannot_be_marked_on_a_holiday(): void
    {
        $f = $this->makeSchool();
        $profile = StaffProfile::factory()->forUser($f['teacher'])->create();

        $this->actingAs($f['admin'], 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => self::PAST_HOLIDAY,
            'records' => [['staff_profile_id' => $profile->id, 'status' => 'present']],
        ])->assertStatus(409)->assertJsonPath('code', 'ATTENDANCE_ON_HOLIDAY');
    }

    public function test_a_transport_trip_cannot_be_started_on_a_holiday(): void
    {
        Queue::fake();
        $f = $this->makeSchool();

        $vehicle = Vehicle::factory()->forSchool($f['school'])->create();
        $driver = Driver::factory()->forSchool($f['school'])->create();
        $route = TransportRoute::factory()->forSchool($f['school'])
            ->withVehicle($vehicle)->withDriver($driver)->create();
        TransportStop::factory()->forRoute($route)->atSequence(1)->create();
        $manager = User::factory()->role(UserRole::TransportManager)->forSchool($f['school'])->create();

        // A trip is always "today", so today has to be the holiday.
        Carbon::setTestNow(Carbon::parse(self::PAST_HOLIDAY.' 07:00:00', 'UTC'));

        $this->actingAs($manager, 'sanctum')
            ->postJson('/api/v1/transport/trips', ['route_id' => $route->id, 'direction' => 'pickup'])
            ->assertStatus(409);
    }

    public function test_leave_taken_entirely_on_a_holiday_is_refused(): void
    {
        $f = $this->makeSchool();
        StaffProfile::factory()->forUser($f['teacher'])->create();

        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/leaves', [
            'leave_type' => 'casual',
            'start_date' => self::FUTURE_HOLIDAY,
            'end_date' => self::FUTURE_HOLIDAY,
            'reason' => 'Family function that turns out to fall on a school holiday.',
        ])->assertStatus(409)->assertJsonPath('code', 'LEAVE_ON_NON_WORKING_DAYS');
    }

    public function test_leave_spanning_a_holiday_does_not_spend_the_holiday(): void
    {
        Queue::fake();
        $f = $this->makeSchool();
        $profile = StaffProfile::factory()->forUser($f['teacher'])->create();

        // Monday the 21st is the holiday; the 22nd and 23rd are working days.
        $leave = $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/leaves', [
            'leave_type' => 'casual',
            'start_date' => self::FUTURE_HOLIDAY,
            'end_date' => '2026-09-23',
            'reason' => 'Away for three days across a school holiday.',
        ])->assertCreated()->json('id');

        $this->actingAs($f['admin'], 'sanctum')
            ->patchJson("/api/v1/leaves/{$leave}/approve")
            ->assertOk();

        // Only the working days are marked as leave: the holiday was never a
        // day anyone was due in, so it is not a day of leave either.
        $marked = StaffAttendance::where('staff_profile_id', $profile->id)
            ->where('status', StaffAttendanceStatus::Leave)
            ->pluck('attendance_date')
            ->map(fn ($date) => $date instanceof Carbon ? $date->toDateString() : (string) $date)
            ->all();

        $this->assertEqualsCanonicalizing(['2026-09-22', '2026-09-23'], $marked);
    }

    public function test_a_teaching_report_cannot_be_filed_for_a_holiday(): void
    {
        $f = $this->makeSchool();

        // The past holiday is a Monday, so a Monday period is the one that
        // would otherwise have been taught that day.
        $entry = TimetableEntry::factory()
            ->forClassSection($f['section'])
            ->forTeacher($f['teacher'])
            ->onDay('monday')
            ->create(['school_id' => $f['school']->id]);

        $this->actingAs($f['teacher'], 'sanctum')->postJson('/api/v1/teaching-reports', [
            'timetable_entry_id' => $entry->id,
            'report_date' => self::PAST_HOLIDAY,
            'topic_taught' => 'Linear equations',
        ])->assertStatus(409)->assertJsonPath('code', 'TEACHING_REPORT_ON_HOLIDAY');
    }

    // -- what a holiday does not stop ------------------------------------

    public function test_the_register_still_opens_on_a_holiday_and_says_why_it_is_closed(): void
    {
        // Blocking the read would leave a teacher staring at an error with no
        // explanation; the register loads and names the holiday instead.
        $f = $this->makeSchool();

        $this->actingAs($f['teacher'], 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$f['section']->id}&date=".self::PAST_HOLIDAY)
            ->assertOk()
            ->assertJsonPath('holiday.name', 'Founders Day');
    }

    public function test_a_holiday_does_not_stop_the_rest_of_the_product(): void
    {
        // Publishing a notice, admitting a student, recording a payment - none
        // of these are teaching days, so the calendar has no say over them.
        Queue::fake();
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')->postJson('/api/v1/announcements', [
            'title' => 'Founders Day is a holiday',
            'body' => 'A reminder that the school is closed on Monday for Founders Day.',
            'audience_type' => 'all_school',
            'channels' => 'sms_in_app',
        ])->assertCreated();
    }

    // -- the two gaps this pins down -------------------------------------

    public function test_attendance_cannot_be_marked_on_a_weekend_either(): void
    {
        // A weekend is not a holiday record, but it is just as much a day the
        // school did not run - and every working-day figure already excludes
        // it. A Saturday register that no percentage counts is worse than no
        // register at all.
        Queue::fake();
        $f = $this->makeSchool();

        $this->submitAttendance($f, self::SATURDAY)
            ->assertStatus(409)
            ->assertJsonPath('code', 'NON_WORKING_DAY')
            ->assertJsonPath('message', 'Attendance cannot be marked on a weekend - the school is closed.');
    }

    public function test_staff_attendance_cannot_be_marked_on_a_weekend_either(): void
    {
        $f = $this->makeSchool();
        $profile = StaffProfile::factory()->forUser($f['teacher'])->create();

        $this->actingAs($f['admin'], 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => self::SATURDAY,
            'records' => [['staff_profile_id' => $profile->id, 'status' => 'present']],
        ])->assertStatus(409)->assertJsonPath('code', 'NON_WORKING_DAY');
    }

    public function test_declaring_a_holiday_late_reports_what_it_takes_out_of_the_count(): void
    {
        // Declaring a holiday after the fact is a legitimate correction; doing
        // it silently is not. The records stay, stop counting, and the admin
        // is told how many so they can clear them.
        Queue::fake();
        $f = $this->makeSchool();

        $this->submitAttendance($f, self::WORKING_DAY)->assertCreated();

        $this->actingAs($f['admin'], 'sanctum')->postJson('/api/v1/holidays', [
            'name' => 'Declared after the fact',
            'type' => 'school_event',
            'start_date' => self::WORKING_DAY,
            'end_date' => self::WORKING_DAY,
        ])->assertCreated()
            ->assertJsonPath('affected_records.attendance', 1)
            ->assertJsonPath('affected_records.staff_attendance', 0)
            ->assertJsonPath('affected_records.teaching_reports', 0);

        $this->assertDatabaseHas('attendances', ['attendance_date' => self::WORKING_DAY]);
    }

    public function test_a_holiday_on_a_clear_week_reports_nothing_to_clear(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')->postJson('/api/v1/holidays', [
            'name' => 'Nothing recorded that day',
            'type' => 'school_event',
            'start_date' => '2026-09-09',
            'end_date' => '2026-09-09',
        ])->assertCreated()->assertJsonPath('affected_records.attendance', 0);
    }
}
