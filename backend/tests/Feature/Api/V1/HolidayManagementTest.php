<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\Holiday;
use App\Models\Period;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\Subject;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class HolidayManagementTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Diwali Break',
            'type' => 'religious',
            'start_date' => '2026-11-09',
            'end_date' => '2026-11-11',
        ], $overrides);
    }

    /** The most recent past Monday - a weekday that is safely in the past for attendance/report dates. */
    private function pastMonday(int $plusDays = 0): string
    {
        return Carbon::now()->startOfWeek(Carbon::MONDAY)->subWeek()->addDays($plusDays)->toDateString();
    }

    // ── create ──────────────────────────────────────────────────────────

    public function test_a_school_admin_can_create_a_holiday_for_their_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/holidays', $this->payload());

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('name', 'Diwali Break')
            ->assertJsonPath('type', 'religious')
            ->assertJsonPath('start_date', '2026-11-09')
            ->assertJsonPath('end_date', '2026-11-11')
            ->assertJsonPath('days', 3);
        $this->assertDatabaseHas('holidays', ['school_id' => $school->id, 'name' => 'Diwali Break']);
    }

    public function test_a_school_admin_cannot_create_a_holiday_for_another_school(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload(['school_id' => $otherSchool->id]))
            ->assertCreated()
            ->assertJsonPath('school_id', $school->id);
    }

    public function test_a_super_admin_can_create_a_holiday_for_any_school(): void
    {
        $school = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload(['school_id' => $school->id]))
            ->assertCreated()
            ->assertJsonPath('school_id', $school->id);
    }

    public function test_a_super_admin_must_supply_a_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload())
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_non_admin_roles_cannot_create_holidays(): void
    {
        $school = School::factory()->create();

        foreach ([UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->postJson('/api/v1/holidays', $this->payload())->assertForbidden();
        }
    }

    public function test_a_sub_admin_can_manage_holidays_like_the_head_admin(): void
    {
        $school = School::factory()->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($subAdmin, 'sanctum')->postJson('/api/v1/holidays', $this->payload())->assertCreated();
    }

    public function test_a_single_day_holiday_has_one_day(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload(['start_date' => '2026-08-15', 'end_date' => '2026-08-15']))
            ->assertCreated()
            ->assertJsonPath('days', 1);
    }

    // ── validation ──────────────────────────────────────────────────────

    public function test_required_fields_and_formats_are_validated(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/holidays', ['name' => '', 'type' => 'party', 'start_date' => 'soon', 'end_date' => null])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['name', 'type', 'start_date', 'end_date']]]);
    }

    public function test_the_end_date_must_not_precede_the_start_date(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload(['start_date' => '2026-11-11', 'end_date' => '2026-11-09']))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['end_date']]]);
    }

    public function test_the_name_is_limited_to_100_characters(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload(['name' => str_repeat('a', 101)]))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['name']]]);
    }

    public function test_overlapping_holidays_in_the_same_school_are_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        Holiday::factory()->forSchool($school)->onDates('2026-11-10', '2026-11-12')->create(['name' => 'Existing']);

        foreach ([['2026-11-09', '2026-11-10'], ['2026-11-11', '2026-11-11'], ['2026-11-12', '2026-11-20'], ['2026-11-01', '2026-11-30']] as [$start, $end]) {
            $this->actingAs($admin, 'sanctum')
                ->postJson('/api/v1/holidays', $this->payload(['start_date' => $start, 'end_date' => $end]))
                ->assertConflict()
                ->assertJsonPath('code', 'HOLIDAY_OVERLAP');
        }
    }

    public function test_adjacent_holidays_do_not_overlap(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        Holiday::factory()->forSchool($school)->onDates('2026-11-10', '2026-11-12')->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/holidays', $this->payload(['start_date' => '2026-11-13', 'end_date' => '2026-11-13']))
            ->assertCreated();
    }

    public function test_the_same_dates_may_be_a_holiday_in_a_different_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        Holiday::factory()->onDates('2026-11-09', '2026-11-11')->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/holidays', $this->payload())->assertCreated();
    }

    // ── list / show ─────────────────────────────────────────────────────

    public function test_everyone_in_a_school_can_list_its_holidays_ordered_by_date_but_not_other_schools(): void
    {
        $school = School::factory()->create();
        Holiday::factory()->forSchool($school)->onDates('2026-12-25')->create(['name' => 'Christmas']);
        Holiday::factory()->forSchool($school)->onDates('2026-08-15')->create(['name' => 'Independence Day']);
        Holiday::factory()->onDates('2026-08-15')->create(['name' => 'Elsewhere']);
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $response = $this->actingAs($teacher, 'sanctum')->getJson('/api/v1/holidays');

        $response->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.name', 'Independence Day')
            ->assertJsonPath('data.1.name', 'Christmas');
    }

    public function test_the_list_can_be_filtered_to_a_date_window(): void
    {
        $school = School::factory()->create();
        Holiday::factory()->forSchool($school)->onDates('2026-08-15')->create(['name' => 'August']);
        Holiday::factory()->forSchool($school)->onDates('2026-10-30', '2026-11-02')->create(['name' => 'Straddles']);
        Holiday::factory()->forSchool($school)->onDates('2026-12-25')->create(['name' => 'December']);
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $response = $this->actingAs($teacher, 'sanctum')
            ->getJson('/api/v1/holidays?date_from=2026-11-01&date_to=2026-11-30');

        $response->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Straddles');
    }

    public function test_a_super_admin_can_filter_the_list_by_school(): void
    {
        $school = School::factory()->create();
        Holiday::factory()->forSchool($school)->create();
        Holiday::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/holidays')->assertOk()->assertJsonCount(2, 'data');
        $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/v1/holidays?school_id={$school->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.school_id', $school->id);
    }

    public function test_a_holiday_from_another_school_cannot_be_viewed(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $foreign = Holiday::factory()->create();

        $this->actingAs($teacher, 'sanctum')->getJson("/api/v1/holidays/{$foreign->id}")->assertForbidden();
    }

    // ── update / delete ─────────────────────────────────────────────────

    public function test_a_school_admin_can_update_a_holiday(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $holiday = Holiday::factory()->forSchool($school)->onDates('2026-11-09', '2026-11-11')->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/holidays/{$holiday->id}", ['name' => 'Diwali', 'end_date' => '2026-11-13'])
            ->assertOk()
            ->assertJsonPath('name', 'Diwali')
            ->assertJsonPath('end_date', '2026-11-13')
            ->assertJsonPath('days', 5);
    }

    public function test_updating_only_the_start_date_past_the_end_date_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $holiday = Holiday::factory()->forSchool($school)->onDates('2026-11-09', '2026-11-11')->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/holidays/{$holiday->id}", ['start_date' => '2026-11-12'])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['start_date']]]);
    }

    public function test_updating_a_holiday_onto_another_one_is_rejected_but_onto_itself_is_fine(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $holiday = Holiday::factory()->forSchool($school)->onDates('2026-11-09', '2026-11-11')->create();
        Holiday::factory()->forSchool($school)->onDates('2026-11-16', '2026-11-16')->create(['name' => 'Other']);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/holidays/{$holiday->id}", ['end_date' => '2026-11-16'])
            ->assertConflict()
            ->assertJsonPath('code', 'HOLIDAY_OVERLAP');
        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/holidays/{$holiday->id}", ['end_date' => '2026-11-13'])
            ->assertOk();
    }

    public function test_a_school_admin_cannot_update_or_delete_another_schools_holiday(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $foreign = Holiday::factory()->create();

        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/holidays/{$foreign->id}", ['name' => 'X'])->assertForbidden();
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/holidays/{$foreign->id}")->assertForbidden();
        $this->assertDatabaseHas('holidays', ['id' => $foreign->id]);
    }

    public function test_a_school_admin_can_delete_a_holiday_and_a_teacher_cannot(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $holiday = Holiday::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/holidays/{$holiday->id}")->assertForbidden();
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/holidays/{$holiday->id}")->assertNoContent();
        $this->assertDatabaseMissing('holidays', ['id' => $holiday->id]);
    }

    // ── integration: student attendance ─────────────────────────────────

    public function test_the_student_register_names_the_holiday_and_marking_is_blocked(): void
    {
        $school = School::factory()->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = ClassSection::factory()->forClass($schoolClass)->withClassTeacher($teacher)->create();
        $students = Student::factory()->forSection($section)->count(2)->create();
        $date = $this->pastMonday();
        Holiday::factory()->forSchool($school)->onDates($date)->create(['name' => 'Founders Day']);

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date={$date}")
            ->assertOk()
            ->assertJsonPath('holiday.name', 'Founders Day')
            ->assertJsonPath('holiday.type', 'national');

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => $date,
            'records' => $students->map(fn (Student $s) => ['student_id' => $s->id, 'status' => 'present'])->all(),
        ])->assertConflict()->assertJsonPath('code', 'ATTENDANCE_ON_HOLIDAY');
        $this->assertDatabaseCount('attendances', 0);

        // The day after is a normal working day - the register says so and marking works.
        $nextDay = $this->pastMonday(1);
        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date={$nextDay}")
            ->assertOk()
            ->assertJsonPath('holiday', null);
        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => $nextDay,
            'records' => $students->map(fn (Student $s) => ['student_id' => $s->id, 'status' => 'present'])->all(),
        ])->assertCreated();
    }

    public function test_another_schools_holiday_does_not_block_this_schools_attendance(): void
    {
        $school = School::factory()->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = ClassSection::factory()->forClass($schoolClass)->withClassTeacher($teacher)->create();
        $students = Student::factory()->forSection($section)->count(1)->create();
        $date = $this->pastMonday();
        Holiday::factory()->onDates($date)->create();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => $date,
            'records' => [['student_id' => $students->first()->id, 'status' => 'present']],
        ])->assertCreated();
    }

    // ── integration: staff attendance ───────────────────────────────────

    public function test_the_staff_register_names_the_holiday_and_marking_is_blocked(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $profile = StaffProfile::factory()->forUser($teacher)->create();
        $date = $this->pastMonday();
        Holiday::factory()->forSchool($school)->onDates($date, $this->pastMonday(2))->type('vacation')->create(['name' => 'Autumn Break']);

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/v1/staff-attendance/register?date={$date}")
            ->assertOk()
            ->assertJsonPath('holiday.name', 'Autumn Break')
            ->assertJsonPath('holiday.type', 'vacation');

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => $this->pastMonday(1),
            'records' => [['staff_profile_id' => $profile->id, 'status' => 'present']],
        ])->assertConflict()->assertJsonPath('code', 'ATTENDANCE_ON_HOLIDAY');
        $this->assertDatabaseCount('staff_attendances', 0);

        $this->actingAs($admin, 'sanctum')->patchJson('/api/v1/staff-attendance', [
            'attendance_date' => $this->pastMonday(1),
            'records' => [['staff_profile_id' => $profile->id, 'status' => 'present']],
        ])->assertConflict()->assertJsonPath('code', 'ATTENDANCE_ON_HOLIDAY');
    }

    // ── integration: daily teaching reports ─────────────────────────────

    public function test_a_teaching_report_dated_on_a_holiday_is_rejected_and_the_summary_shows_the_holiday(): void
    {
        $school = School::factory()->create();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hod)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        StaffProfile::factory()->forUser($teacher)->forDepartment($department)->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $section = ClassSection::factory()->forClass(SchoolClass::factory()->forAcademicYear($academicYear)->create())->create();
        $entry = TimetableEntry::factory()
            ->forClassSection($section)
            ->forSubject(Subject::factory()->forDepartment($department)->create())
            ->forTeacher($teacher)
            ->forPeriod(Period::factory()->forSchool($school)->create())
            ->onDay('monday')
            ->create(['school_id' => $school->id]);
        $monday = $this->pastMonday();
        Holiday::factory()->forSchool($school)->onDates($monday)->create(['name' => 'Republic Day']);

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/teaching-reports', [
            'timetable_entry_id' => $entry->id,
            'report_date' => $monday,
            'topic_taught' => 'Fractions',
        ])->assertConflict()->assertJsonPath('code', 'TEACHING_REPORT_ON_HOLIDAY');
        $this->assertDatabaseCount('daily_teaching_reports', 0);

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/teaching-reports/summary?date={$monday}")
            ->assertOk()
            ->assertJsonPath('scheduled', 0)
            ->assertJsonPath('pending', 0)
            ->assertJsonPath('holiday', 'Republic Day');

        // A non-holiday Monday is unaffected.
        $previousMonday = Carbon::parse($monday)->subWeek()->toDateString();
        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/teaching-reports/summary?date={$previousMonday}")
            ->assertOk()
            ->assertJsonPath('scheduled', 1)
            ->assertJsonPath('holiday', null);
    }
}
