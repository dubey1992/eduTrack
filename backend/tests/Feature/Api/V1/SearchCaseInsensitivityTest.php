<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Announcement;
use App\Models\ClassSection;
use App\Models\EarlyAccessRequest;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Searching finds a record whatever case it is typed in.
 *
 * Written for the PostgreSQL migration (docs/python-migration.md, M2), and
 * every test here fails on PostgreSQL without the fix while passing on MySQL,
 * which is the whole point of it. MySQL's default collation is
 * case-insensitive, so `like` there finds "Abhishek" when you type "abhishek";
 * PostgreSQL's `like` does not. Nothing errors and nothing else fails - the
 * search simply, quietly, finds less than it used to.
 *
 * Before this file the suite had no search coverage at all, which is how a
 * whole feature could have crossed to another database and lost half its
 * behaviour without a single red test.
 */
class SearchCaseInsensitivityTest extends TestCase
{
    use RefreshDatabase;

    private School $school;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->school = School::factory()->create(['name' => 'Sunrise Public School']);
        $this->admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->school)->create();
    }

    /**
     * @return array<int, string>
     */
    private function search(string $endpoint, string $term, string $field): array
    {
        $response = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/v1/{$endpoint}?search=".urlencode($term))
            ->assertOk();

        return array_column($response->json('data'), $field);
    }

    public function test_a_student_is_found_however_the_name_is_typed(): void
    {
        $year = AcademicYear::factory()->forSchool($this->school)->create();
        $class = SchoolClass::factory()->forAcademicYear($year)->create();
        $section = ClassSection::factory()->forClass($class)->create();

        Student::factory()->create([
            'school_id' => $this->school->id,
            'class_section_id' => $section->id,
            'first_name' => 'Abhishek',
            'last_name' => 'Williams',
            'admission_number' => 'SPS0001',
        ]);

        foreach (['Abhishek', 'abhishek', 'ABHISHEK', 'aBhIsHeK'] as $term) {
            $this->assertSame(
                ['Abhishek'],
                $this->search('students', $term, 'first_name'),
                "searching students for '{$term}' should have found Abhishek",
            );
        }
    }

    public function test_an_admission_number_is_found_in_either_case(): void
    {
        $year = AcademicYear::factory()->forSchool($this->school)->create();
        $class = SchoolClass::factory()->forAcademicYear($year)->create();
        $section = ClassSection::factory()->forClass($class)->create();

        Student::factory()->create([
            'school_id' => $this->school->id,
            'class_section_id' => $section->id,
            'first_name' => 'Meera',
            'admission_number' => 'SPS0042',
        ]);

        // Admission numbers are printed on cards and read back by hand, so
        // they are exactly the thing somebody types in lowercase.
        $this->assertSame(['SPS0042'], $this->search('students', 'sps0042', 'admission_number'));
    }

    public function test_an_employee_is_found_however_the_name_is_typed(): void
    {
        // The name searched is the one on the login account, not the
        // employment profile - StaffProfileService searches through the user
        // relation.
        $user = User::factory()->role(UserRole::Teacher)->forSchool($this->school)->create([
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
        ]);

        StaffProfile::factory()->create([
            'school_id' => $this->school->id,
            'user_id' => $user->id,
        ]);

        foreach (['Priya', 'priya', 'PRIYA'] as $term) {
            $this->assertSame(
                ['Priya'],
                $this->search('staff', $term, 'first_name'),
                "searching staff for '{$term}' should have found Priya",
            );
        }
    }

    public function test_an_early_access_request_is_found_however_it_is_typed(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        EarlyAccessRequest::factory()->create([
            'school_name' => 'Greenfield Academy',
            'contact_name' => 'Nneka Okafor',
            'email' => 'head@greenfield.test',
        ]);

        foreach (['greenfield', 'GREENFIELD', 'Greenfield'] as $term) {
            $names = array_column(
                $this->actingAs($superAdmin, 'sanctum')
                    ->getJson('/api/v1/early-access?q='.urlencode($term))
                    ->assertOk()
                    ->json('data'),
                'school_name'
            );

            $this->assertSame(['Greenfield Academy'], $names, "searching early access for '{$term}' found nothing");
        }
    }

    public function test_an_announcement_is_found_however_it_is_typed(): void
    {
        Announcement::factory()->create([
            'school_id' => $this->school->id,
            'published_by' => $this->admin->id,
            'title' => 'Sports Day Rescheduled',
        ]);

        foreach (['sports day', 'SPORTS DAY', 'Sports Day'] as $term) {
            // `q`, not `search` - announcements names its filter differently
            // from students and staff. Sending the wrong one here made this
            // test pass against an unfiltered list, proving nothing.
            $titles = array_column(
                $this->actingAs($this->admin, 'sanctum')
                    ->getJson('/api/v1/announcements?q='.urlencode($term))
                    ->assertOk()
                    ->json('data'),
                'title'
            );

            $this->assertSame(['Sports Day Rescheduled'], $titles, "searching announcements for '{$term}' found nothing");
        }
    }

    public function test_a_search_that_matches_nothing_still_matches_nothing(): void
    {
        // The other half of the claim: case-insensitive must not mean
        // everything-matches.
        $year = AcademicYear::factory()->forSchool($this->school)->create();
        $class = SchoolClass::factory()->forAcademicYear($year)->create();
        $section = ClassSection::factory()->forClass($class)->create();

        Student::factory()->create([
            'school_id' => $this->school->id,
            'class_section_id' => $section->id,
            'first_name' => 'Abhishek',
            'admission_number' => 'SPS0001',
        ]);

        $this->assertSame([], $this->search('students', 'Zainab', 'first_name'));
    }
}
