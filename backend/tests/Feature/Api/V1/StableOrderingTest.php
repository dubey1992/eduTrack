<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\Holiday;
use App\Models\Department;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\Subject;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A paginated list orders by something unique, so paging through it shows
 * every record exactly once.
 *
 * The lists here order by a name, and names repeat. Without a tiebreaker the
 * database is free to return equal rows in any order it likes - and it does,
 * differently, between MySQL and PostgreSQL and even between two runs of the
 * same query. Page one then ends with a row that page two also begins with,
 * and some other row is never shown at all.
 *
 * Found by asking the PHP and Python backends for the same list and diffing
 * the answers (docs/python-migration.md, M9): they disagreed about the order
 * of two students who shared a first name. Neither backend's own tests could
 * have seen it, because each was internally consistent.
 *
 * Every assertion below fails without the `orderBy('id')` that accompanies
 * this file, and they are about paging rather than about order: the exact
 * sequence is not the contract, but "each record once" is.
 */
class StableOrderingTest extends TestCase
{
    use RefreshDatabase;

    private School $school;

    private User $root;

    protected function setUp(): void
    {
        parent::setUp();

        $this->school = School::factory()->create(['name' => 'Sunrise Public School']);
        $this->root = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);
    }

    public function test_paging_through_students_who_share_a_name_shows_each_once(): void
    {
        $section = $this->section();

        // Six students, one name between them. Nothing but the tiebreaker
        // distinguishes their position in the list.
        foreach (range(1, 6) as $index) {
            Student::factory()->create([
                'school_id' => $this->school->id,
                'class_section_id' => $section->id,
                'first_name' => 'Aarav',
                'last_name' => 'Sharma',
                'admission_number' => 'ADM-'.$index,
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/students', 6);
    }

    public function test_paging_through_users_who_share_a_name_shows_each_once(): void
    {
        foreach (range(1, 6) as $index) {
            User::factory()->role(UserRole::Teacher)->forSchool($this->school)->create([
                'first_name' => 'Priya',
                'last_name' => 'Nair',
                'email' => 'priya'.$index.'@example.invalid',
            ]);
        }

        // Plus the Super Admin, who has a name of their own.
        $this->assertEachRecordAppearsOnce('/api/v1/users', User::query()->count());
    }

    public function test_paging_through_schools_that_share_a_name_shows_each_once(): void
    {
        foreach (range(1, 6) as $index) {
            School::factory()->create([
                'name' => 'Greenfield Academy',
                'email' => 'greenfield'.$index.'@example.invalid',
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/schools', School::query()->count());
    }

    public function test_paging_through_academic_years_that_start_together_shows_each_once(): void
    {
        // Years repeat their start date constantly - every school in a group
        // begins on the same April day - so this list ties more often than
        // any other.
        foreach (range(1, 6) as $index) {
            AcademicYear::factory()->create([
                'school_id' => $this->school->id,
                'name' => '2026-27 #'.$index,
                'start_date' => '2026-04-01',
                'end_date' => '2027-03-31',
                'is_current' => false,
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/academic-years', 6);
    }

    public function test_paging_through_departments_that_share_a_name_shows_each_once(): void
    {
        // A department name is unique within a school and not across them, so
        // a Super Admin's list ties on almost every row: every school has a
        // Science department.
        foreach (range(1, 6) as $index) {
            Department::factory()->create([
                'school_id' => School::factory()->create([
                    'email' => 'dept'.$index.'@example.invalid',
                ])->id,
                'name' => 'Science',
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/departments', 6);
    }

    public function test_paging_through_subjects_that_share_a_name_shows_each_once(): void
    {
        foreach (range(1, 6) as $index) {
            $school = School::factory()->create(['email' => 'subj'.$index.'@example.invalid']);

            Subject::factory()->create([
                'school_id' => $school->id,
                'department_id' => Department::factory()->create(['school_id' => $school->id])->id,
                'name' => 'Mathematics',
                'code' => 'MATH',
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/subjects', 6);
    }

    public function test_paging_through_staff_who_share_an_employee_id_shows_each_once(): void
    {
        // An employee id is unique within a school and not across them, so
        // EMP-001 exists at every school on the platform.
        foreach (range(1, 6) as $index) {
            $school = School::factory()->create(['email' => 'staff'.$index.'@example.invalid']);

            StaffProfile::factory()->create([
                'school_id' => $school->id,
                'user_id' => User::factory()->role(UserRole::Teacher)->forSchool($school)->create([
                    'email' => 'teacher'.$index.'@example.invalid',
                ])->id,
                'employee_id' => 'EMP-001',
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/staff', 6);
    }

    public function test_paging_through_holidays_that_start_together_shows_each_once(): void
    {
        // Schools share dates constantly: every school in a country closes on
        // the same national holiday.
        foreach (range(1, 6) as $index) {
            Holiday::factory()->create([
                'school_id' => School::factory()->create([
                    'email' => 'holiday'.$index.'@example.invalid',
                ])->id,
                'name' => 'Republic Day',
                'start_date' => '2027-01-26',
                'end_date' => '2027-01-26',
            ]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/holidays', 6);
    }

    public function test_the_attendance_list_honours_per_page(): void
    {
        // Not an ordering test, but found the same way and belonging with the
        // others: this list dropped per_page on its way to the service, so it
        // was the one paginated endpoint that always returned twenty however
        // small a page the caller asked for.
        $section = $this->section();

        foreach (range(1, 3) as $index) {
            $student = Student::factory()->create([
                'school_id' => $this->school->id,
                'class_section_id' => $section->id,
                'admission_number' => 'ADM-P'.$index,
            ]);

            Attendance::factory()->create([
                'school_id' => $this->school->id,
                'academic_year_id' => $section->schoolClass->academic_year_id,
                'class_section_id' => $section->id,
                'student_id' => $student->id,
                'marked_by' => $this->root->id,
            ]);
        }

        $response = $this->actingAs($this->root)->getJson('/api/v1/attendance?per_page=2');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
        $this->assertSame(2, $response->json('meta.per_page'));
    }

    public function test_paging_through_leave_applied_for_together_shows_each_once(): void
    {
        // A leave list is ordered newest first, and created_at is where this
        // one ties: a school admin applying on behalf of several staff, or a
        // seeded import, writes rows within the same second.
        $department = Department::factory()->create(['school_id' => $this->school->id]);
        $applied = now();

        foreach (range(1, 6) as $index) {
            $user = User::factory()->role(UserRole::Teacher)->forSchool($this->school)->create([
                'email' => 'leave'.$index.'@example.invalid',
            ]);

            StaffLeave::factory()
                ->forStaff(StaffProfile::factory()->forUser($user)->forDepartment($department)->create())
                ->create(['created_at' => $applied, 'updated_at' => $applied]);
        }

        $this->assertEachRecordAppearsOnce('/api/v1/leaves', 6);
    }

    /**
     * Walks every page one record at a time and asserts the ids seen are
     * exactly the ids that exist - no repeats, nothing missed.
     */
    private function assertEachRecordAppearsOnce(string $path, int $expected): void
    {
        $seen = [];

        for ($page = 1; $page <= $expected; $page++) {
            $response = $this->actingAs($this->root)->getJson($path.'?per_page=1&page='.$page);

            $response->assertOk();
            $seen[] = $response->json('data.0.id');
        }

        $this->assertCount(
            $expected,
            array_unique($seen),
            'paging through '.$path.' returned '.count(array_unique($seen))
            .' distinct records out of '.$expected.': '.implode(',', $seen)
        );
    }

    private function section(): ClassSection
    {
        $year = AcademicYear::factory()->create(['school_id' => $this->school->id]);
        $class = SchoolClass::factory()->create([
            'school_id' => $this->school->id,
            'academic_year_id' => $year->id,
        ]);

        return ClassSection::factory()->create(['school_class_id' => $class->id]);
    }
}
