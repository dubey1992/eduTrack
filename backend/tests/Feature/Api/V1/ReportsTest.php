<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AttendanceStatus;
use App\Enums\StaffAttendanceStatus;
use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\Holiday;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffAttendance;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Phase 18's reports.
 *
 * The figure that matters in all of them is the denominator: every rate is
 * out of the days the school actually ran, taken from the same holiday
 * calendar that decides whether a register may be taken at all. A report that
 * counted weekends or holidays would contradict the screen that refuses to
 * mark them.
 */
class ReportsTest extends TestCase
{
    use RefreshDatabase;

    /** Monday 7 to Friday 11 September: five working days. */
    private const string FROM = '2026-09-07';

    private const string TO = '2026-09-11';

    protected function setUp(): void
    {
        parent::setUp();
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
            'student' => Student::factory()->forSection($section)->create([
                'first_name' => 'Arjun',
                'last_name' => 'Kumar',
                'admission_number' => 'STU-0042',
            ]),
            'admin' => User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(),
        ];
    }

    private function markStudent(array $f, string $date, AttendanceStatus $status): void
    {
        Attendance::create([
            'school_id' => $f['school']->id,
            'academic_year_id' => $f['section']->schoolClass->academic_year_id,
            'class_section_id' => $f['section']->id,
            'student_id' => $f['student']->id,
            'attendance_date' => $date,
            'status' => $status,
            'marked_by' => $f['teacher']->id,
        ]);
    }

    private function url(string $report, array $params = []): string
    {
        return '/api/v1/reports/'.$report.'?'.http_build_query(array_merge(
            ['from' => self::FROM, 'to' => self::TO],
            $params,
        ));
    }

    // -- student attendance ----------------------------------------------

    public function test_the_rate_is_out_of_the_days_the_school_ran(): void
    {
        $f = $this->makeSchool();

        // Present on three of the five working days, absent on one, and the
        // fifth never marked at all.
        $this->markStudent($f, '2026-09-07', AttendanceStatus::Present);
        $this->markStudent($f, '2026-09-08', AttendanceStatus::Present);
        $this->markStudent($f, '2026-09-09', AttendanceStatus::Present);
        $this->markStudent($f, '2026-09-10', AttendanceStatus::Absent);

        $response = $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance'))
            ->assertOk();

        $response->assertJsonPath('range.working_days', 5)
            ->assertJsonPath('rows.0.present', 3)
            ->assertJsonPath('rows.0.absent', 1)
            // Said plainly rather than folded into "absent": nobody claimed
            // this student was away, only that no register was taken.
            ->assertJsonPath('rows.0.not_marked', 1);

        // Compared numerically: JSON renders 60.0 as 60, so a strict path
        // compare against a float would fail on a correct figure.
        $this->assertEqualsWithDelta(60, $response->json('rows.0.attendance_rate'), 0.01);
    }

    public function test_a_holiday_inside_the_range_shrinks_the_denominator(): void
    {
        $f = $this->makeSchool();
        Holiday::factory()->forSchool($f['school'])->create([
            'name' => 'Founders Day',
            'start_date' => '2026-09-09',
            'end_date' => '2026-09-09',
        ]);

        $this->markStudent($f, '2026-09-07', AttendanceStatus::Present);
        $this->markStudent($f, '2026-09-08', AttendanceStatus::Present);
        $this->markStudent($f, '2026-09-10', AttendanceStatus::Present);
        $this->markStudent($f, '2026-09-11', AttendanceStatus::Present);

        // Four working days, not five, and four out of four is full marks -
        // the child is not penalised for a day the school was shut.
        $response = $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance'))
            ->assertOk()
            ->assertJsonPath('range.working_days', 4);

        $this->assertEqualsWithDelta(100, $response->json('rows.0.attendance_rate'), 0.01);
    }

    public function test_a_mark_left_on_a_day_that_later_became_a_holiday_stops_counting(): void
    {
        // The other half of the same rule: the record survives, but it is no
        // longer a working day, so it cannot inflate a rate measured against
        // working days.
        $f = $this->makeSchool();
        $this->markStudent($f, '2026-09-09', AttendanceStatus::Present);

        Holiday::factory()->forSchool($f['school'])->create([
            'name' => 'Declared later',
            'start_date' => '2026-09-09',
            'end_date' => '2026-09-09',
        ]);

        $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance'))
            ->assertOk()
            ->assertJsonPath('range.working_days', 4)
            ->assertJsonPath('rows.0.present', 0);
    }

    public function test_a_range_of_only_holidays_has_no_rate_rather_than_zero(): void
    {
        // "0%" would read as everybody having been absent.
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance', ['from' => '2026-09-12', 'to' => '2026-09-13']))
            ->assertOk()
            ->assertJsonPath('range.working_days', 0)
            ->assertJsonPath('rows.0.attendance_rate', null);
    }

    public function test_a_report_cannot_run_past_today(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance', ['to' => '2026-12-31']))
            ->assertStatus(422)
            ->assertJsonPath('details.errors.to.0', 'A report cannot run past today.');
    }

    public function test_the_report_can_be_narrowed_to_one_class_section(): void
    {
        $f = $this->makeSchool();
        $other = ClassSection::factory()
            ->forClass(SchoolClass::factory()->forAcademicYear(
                AcademicYear::factory()->forSchool($f['school'])->create()
            )->create(['name' => 'Grade 9']))
            ->create(['name' => 'B']);
        Student::factory()->forSection($other)->create();

        $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance', ['class_section_id' => $f['section']->id]))
            ->assertOk()
            ->assertJsonCount(1, 'rows')
            ->assertJsonPath('rows.0.admission_number', 'STU-0042');
    }

    // -- staff attendance -------------------------------------------------

    public function test_a_half_day_counts_as_half_a_day_present(): void
    {
        $f = $this->makeSchool();
        $profile = StaffProfile::factory()->forUser($f['teacher'])->create();

        foreach (['2026-09-07', '2026-09-08', '2026-09-09'] as $date) {
            StaffAttendance::create([
                'school_id' => $f['school']->id,
                'staff_profile_id' => $profile->id,
                'attendance_date' => $date,
                'status' => StaffAttendanceStatus::Present,
                'marked_by' => $f['admin']->id,
            ]);
        }
        StaffAttendance::create([
            'school_id' => $f['school']->id,
            'staff_profile_id' => $profile->id,
            'attendance_date' => '2026-09-10',
            'status' => StaffAttendanceStatus::HalfDay,
            'marked_by' => $f['admin']->id,
        ]);

        // Three full days plus a half, rounded, out of five.
        $response = $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('staff-attendance'))
            ->assertOk()
            ->assertJsonPath('rows.0.present', 3)
            ->assertJsonPath('rows.0.half_day', 1);

        $this->assertEqualsWithDelta(80, $response->json('rows.0.attendance_rate'), 0.01);
    }

    // -- who may look -----------------------------------------------------

    public function test_a_teacher_cannot_pull_a_school_wide_report(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['teacher'], 'sanctum')
            ->getJson($this->url('student-attendance'))
            ->assertForbidden();
    }

    public function test_a_head_of_department_may_see_staff_but_not_students(): void
    {
        $f = $this->makeSchool();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($f['school'])->create();

        $this->actingAs($hod, 'sanctum')->getJson($this->url('staff-attendance'))->assertOk();
        $this->actingAs($hod, 'sanctum')->getJson($this->url('student-attendance'))->assertForbidden();
    }

    public function test_a_head_of_department_only_sees_their_own_departments(): void
    {
        $f = $this->makeSchool();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($f['school'])->create();

        $mine = Department::factory()->forSchool($f['school'])->create(['hod_user_id' => $hod->id]);
        $theirs = Department::factory()->forSchool($f['school'])->create();

        StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($f['school'])->create())
            ->create(['department_id' => $mine->id, 'employee_id' => 'EMP-MINE']);
        StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($f['school'])->create())
            ->create(['department_id' => $theirs->id, 'employee_id' => 'EMP-THEIRS']);

        $rows = $this->actingAs($hod, 'sanctum')->getJson($this->url('staff-attendance'))
            ->assertOk()
            ->json('rows');

        $this->assertSame(['EMP-MINE'], array_column($rows, 'employee_id'));
    }

    public function test_a_transport_manager_sees_transport_and_nothing_else(): void
    {
        $f = $this->makeSchool();
        $manager = User::factory()->role(UserRole::TransportManager)->forSchool($f['school'])->create();

        $this->actingAs($manager, 'sanctum')->getJson($this->url('transport-usage'))->assertOk();
        $this->actingAs($manager, 'sanctum')->getJson($this->url('staff-attendance'))->assertForbidden();
    }

    public function test_a_school_admin_cannot_report_on_another_school(): void
    {
        $f = $this->makeSchool();
        $other = $this->makeSchool();
        $this->markStudent($other, '2026-09-07', AttendanceStatus::Present);

        // The school_id is simply ignored for a school user - their report is
        // always their own school's.
        $rows = $this->actingAs($f['admin'], 'sanctum')
            ->getJson($this->url('student-attendance', ['school_id' => $other['school']->id]))
            ->assertOk()
            ->json('rows');

        $this->assertCount(1, $rows);
        $this->assertSame($f['student']->id, $rows[0]['student_id']);
    }

    public function test_a_super_admin_must_name_a_school(): void
    {
        $this->makeSchool();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson($this->url('student-attendance'))
            ->assertStatus(422)
            ->assertJsonPath('details.errors.school_id.0', 'Pick a school to report on.');
    }

    public function test_an_unauthenticated_caller_gets_nothing(): void
    {
        $this->getJson($this->url('student-attendance'))->assertUnauthorized();
    }

    // -- csv ---------------------------------------------------------------

    public function test_the_same_figures_come_back_as_a_csv(): void
    {
        $f = $this->makeSchool();
        $this->markStudent($f, '2026-09-07', AttendanceStatus::Present);

        $response = $this->actingAs($f['admin'], 'sanctum')
            ->get($this->url('student-attendance', ['format' => 'csv']))
            ->assertOk();

        $this->assertStringContainsString('text/csv', $response->headers->get('Content-Type'));
        $this->assertStringContainsString('student-attendance-2026-09-07-to-2026-09-11.csv', $response->headers->get('Content-Disposition'));

        $body = $response->streamedContent();
        $this->assertStringContainsString('Admission No.', $body);
        $this->assertStringContainsString('STU-0042', $body);
        $this->assertStringContainsString('Arjun Kumar', $body);
    }

    public function test_the_csv_opens_cleanly_in_a_spreadsheet(): void
    {
        // Without a byte order mark Excel reads the file as the system
        // codepage and mangles any non-ASCII name.
        $f = $this->makeSchool();

        $body = $this->actingAs($f['admin'], 'sanctum')
            ->get($this->url('student-attendance', ['format' => 'csv']))
            ->assertOk()
            ->streamedContent();

        $this->assertStringStartsWith("\xEF\xBB\xBF", $body);
    }

    public function test_every_report_answers_as_csv(): void
    {
        $f = $this->makeSchool();

        foreach (['student-attendance', 'staff-attendance', 'teaching-coverage', 'transport-usage'] as $report) {
            $this->actingAs($f['admin'], 'sanctum')
                ->get($this->url($report, ['format' => 'csv']))
                ->assertOk();
        }
    }
}
