<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\School;
use App\Models\SchoolClass;
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
