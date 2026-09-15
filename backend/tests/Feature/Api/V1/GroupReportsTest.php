<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AttendanceStatus;
use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\Holiday;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * One report across a whole group.
 *
 * The figure that matters is the combined rate. Every branch measures against
 * its own working days - its own holiday calendar, its own timezone - so the
 * group total cannot be an average of the branches' percentages, and the
 * tests here are mostly about proving it is not.
 */
class GroupReportsTest extends TestCase
{
    use RefreshDatabase;

    private School $group;

    private School $north;

    private School $south;

    private User $groupAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->group = School::factory()->create(['name' => 'A Group', 'timezone' => 'UTC']);
        $this->north = School::factory()->branchOf($this->group)->create(['name' => 'B North', 'timezone' => 'UTC']);
        $this->south = School::factory()->branchOf($this->group)->create(['name' => 'C South', 'timezone' => 'UTC']);

        $this->groupAdmin = User::factory()->role(UserRole::GroupAdmin)->forSchool($this->group)->create();
    }

    /**
     * @return array<int, Student>
     */
    private function studentsAt(School $school, int $count): array
    {
        $year = AcademicYear::factory()->create(['school_id' => $school->id, 'is_current' => true]);
        $class = SchoolClass::factory()->create(['school_id' => $school->id, 'academic_year_id' => $year->id]);
        $section = ClassSection::factory()->create(['school_class_id' => $class->id]);

        return collect(range(1, $count))
            ->map(fn (int $i) => Student::factory()->create([
                'school_id' => $school->id,
                'class_section_id' => $section->id,
                'admission_number' => "{$school->id}-{$i}",
            ]))
            ->all();
    }

    private function mark(Student $student, string $date, AttendanceStatus $status): void
    {
        Attendance::factory()->create([
            'school_id' => $student->school_id,
            'student_id' => $student->id,
            'class_section_id' => $student->class_section_id,
            'attendance_date' => $date,
            'status' => $status,
        ]);
    }

    private function url(string $report = 'student-attendance', array $extra = []): string
    {
        // A Monday to a Wednesday, so weekends never enter the arithmetic.
        return '/api/v1/reports/'.$report.'?'.http_build_query([
            'from' => '2026-09-07',
            'to' => '2026-09-09',
            ...$extra,
        ]);
    }

    // ── the shape ───────────────────────────────────────────────────────

    public function test_naming_no_branch_reports_on_every_branch(): void
    {
        $this->studentsAt($this->north, 1);
        $this->studentsAt($this->south, 1);

        $response = $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk();

        $this->assertTrue($response->json('group'));
        $this->assertSame(
            ['A Group', 'B North', 'C South'],
            array_column($response->json('branches'), 'school_name'),
        );
        $this->assertSame(3, $response->json('totals.branches'));
    }

    public function test_every_row_says_which_branch_it_came_from(): void
    {
        $this->studentsAt($this->north, 2);
        $this->studentsAt($this->south, 1);

        $rows = $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk()->json('rows');

        $this->assertCount(3, $rows);
        $this->assertSame(
            ['B North' => 2, 'C South' => 1],
            array_count_values(array_column($rows, 'school_name')),
        );
        // The id too, so a client can link back to the branch.
        $this->assertContains($this->north->id, array_column($rows, 'school_id'));
    }

    public function test_naming_a_branch_reports_on_that_branch_alone(): void
    {
        $this->studentsAt($this->north, 2);
        $this->studentsAt($this->south, 5);

        $response = $this->actingAs($this->groupAdmin, 'sanctum')
            ->getJson($this->url('student-attendance', ['school_id' => $this->north->id]))
            ->assertOk();

        $this->assertNull($response->json('group'));
        $this->assertNull($response->json('branches'));
        $this->assertCount(2, $response->json('rows'));
    }

    public function test_a_group_report_never_reaches_outside_the_group(): void
    {
        $outsider = School::factory()->create(['name' => 'Z Elsewhere']);
        $this->studentsAt($outsider, 4);
        $this->studentsAt($this->north, 1);

        $response = $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk();

        $this->assertNotContains('Z Elsewhere', array_column($response->json('branches'), 'school_name'));
        $this->assertSame(1, $response->json('totals.students'));
    }

    // ── the arithmetic ──────────────────────────────────────────────────

    public function test_the_combined_rate_is_weighted_by_size_not_averaged(): void
    {
        // North: 1 student, present all 3 days      -> 100%
        // South: 3 students, present 1 day each     -> 33.3%
        // An average of the two would be 66.7%. The truth is 6 present marks
        // out of 12 possible - 50% - and a big branch must not be outvoted by
        // a small one.
        [$northStudent] = $this->studentsAt($this->north, 1);
        foreach (['2026-09-07', '2026-09-08', '2026-09-09'] as $date) {
            $this->mark($northStudent, $date, AttendanceStatus::Present);
        }

        foreach ($this->studentsAt($this->south, 3) as $student) {
            $this->mark($student, '2026-09-07', AttendanceStatus::Present);
        }

        $totals = $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk()->json('totals');

        $this->assertSame(4, $totals['students']);
        $this->assertSame(6, $totals['present']);
        $this->assertEqualsWithDelta(50.0, $totals['attendance_rate'], 0.05);
    }

    public function test_a_branch_keeps_its_own_working_days(): void
    {
        // A holiday at one branch is not a holiday at the other, so their
        // denominators differ - which is the whole reason the report runs
        // once per branch instead of as one query.
        Holiday::factory()->create([
            'school_id' => $this->south->id,
            'start_date' => '2026-09-08',
            'end_date' => '2026-09-08',
        ]);

        $this->studentsAt($this->north, 1);
        $this->studentsAt($this->south, 1);

        $branches = collect(
            $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk()->json('branches')
        )->keyBy('school_name');

        $this->assertSame(3, $branches['B North']['range']['working_days']);
        $this->assertSame(2, $branches['C South']['range']['working_days']);
    }

    public function test_the_group_range_does_not_pretend_to_have_working_days(): void
    {
        // Adding two schools' working days together is a number that means
        // nothing, so the group range reports the window only.
        $this->studentsAt($this->north, 1);

        $range = $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk()->json('range');

        $this->assertSame('2026-09-07', $range['from']);
        $this->assertSame('2026-09-09', $range['to']);
        $this->assertArrayNotHasKey('working_days', $range);
    }

    public function test_a_group_with_nothing_in_it_still_answers(): void
    {
        $totals = $this->actingAs($this->groupAdmin, 'sanctum')->getJson($this->url())->assertOk()->json('totals');

        $this->assertSame(0, $totals['students']);
        // Not 0% - nobody was absent, there is simply nobody.
        $this->assertNull($totals['attendance_rate']);
    }

    // ── the other three reports ─────────────────────────────────────────

    public function test_staff_attendance_combines_across_branches(): void
    {
        $response = $this->actingAs($this->groupAdmin, 'sanctum')
            ->getJson($this->url('staff-attendance'))
            ->assertOk();

        $this->assertTrue($response->json('group'));
        $this->assertSame(3, $response->json('totals.branches'));
        $this->assertArrayHasKey('staff', $response->json('totals'));
    }

    public function test_teaching_coverage_combines_across_branches(): void
    {
        $response = $this->actingAs($this->groupAdmin, 'sanctum')
            ->getJson($this->url('teaching-coverage'))
            ->assertOk();

        $this->assertTrue($response->json('group'));
        // Periods reported over periods scheduled, across the group - and
        // null rather than zero when nothing was scheduled at all.
        $this->assertSame(0, $response->json('totals.periods_scheduled'));
        $this->assertNull($response->json('totals.coverage_rate'));
    }

    public function test_transport_usage_combines_across_branches(): void
    {
        $response = $this->actingAs($this->groupAdmin, 'sanctum')
            ->getJson($this->url('transport-usage'))
            ->assertOk();

        $this->assertTrue($response->json('group'));
        $this->assertSame(3, $response->json('totals.branches'));
        $this->assertSame(0, $response->json('totals.trips_completed'));
    }

    // ── the export ──────────────────────────────────────────────────────

    public function test_a_group_csv_names_the_branch_on_every_line(): void
    {
        $this->studentsAt($this->north, 1);
        $this->studentsAt($this->south, 1);

        $response = $this->actingAs($this->groupAdmin, 'sanctum')
            ->get($this->url('student-attendance', ['format' => 'csv']))
            ->assertOk();

        $body = $response->streamedContent();
        $lines = array_values(array_filter(explode("\n", trim($body))));

        $this->assertStringContainsString('School,', $lines[0]);
        $this->assertStringContainsString('Admission No.', $lines[0]);
        $this->assertStringContainsString('B North', $lines[1]);
        $this->assertStringContainsString('C South', $lines[2]);
    }

    public function test_a_single_branch_csv_is_unchanged(): void
    {
        $this->studentsAt($this->north, 1);

        $body = $this->actingAs($this->groupAdmin, 'sanctum')
            ->get($this->url('student-attendance', ['school_id' => $this->north->id, 'format' => 'csv']))
            ->assertOk()
            ->streamedContent();

        $heading = explode("\n", $body)[0];
        $this->assertStringContainsString('Admission No.', $heading);
        $this->assertStringNotContainsString('School,', $heading);
    }

    // ── everybody else ──────────────────────────────────────────────────

    public function test_a_school_admin_never_gets_a_group_report(): void
    {
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->north)->create();
        $this->studentsAt($this->north, 1);
        $this->studentsAt($this->south, 1);

        $response = $this->actingAs($admin, 'sanctum')->getJson($this->url())->assertOk();

        $this->assertNull($response->json('group'));
        $this->assertCount(1, $response->json('rows'));
    }

    public function test_a_super_admin_still_names_a_school(): void
    {
        // "Every school on the platform" is not a report.
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson($this->url())
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_a_group_admin_of_a_lone_school_gets_a_plain_report(): void
    {
        $lone = School::factory()->create();
        $admin = User::factory()->role(UserRole::GroupAdmin)->forSchool($lone)->create();
        $this->studentsAt($lone, 1);

        $response = $this->actingAs($admin, 'sanctum')->getJson($this->url())->assertOk();

        // One school is not a group; there is nothing to break down.
        $this->assertNull($response->json('group'));
        $this->assertCount(1, $response->json('rows'));
    }
}
