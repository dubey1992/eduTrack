<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A School Admin whose school belongs to a group.
 *
 * Decided on 2026-09-16: the head of a school answers for its branches, and a
 * branch answers alongside its sisters - so a SCHOOL_ADMIN in a group reads
 * and writes across the whole group, exactly as a GROUP_ADMIN does.
 *
 * Two things this file has to prove, and they pull in opposite directions:
 *
 *  - the group really is reachable, in both directions (a parent looking
 *    down, a branch looking up and sideways);
 *  - and the group is still a wall. A standalone school - which is nearly
 *    every school - must be exactly as isolated as it was before, and no
 *    school may reach another group at all.
 */
class SchoolAdminGroupTest extends TestCase
{
    use RefreshDatabase;

    private School $group;

    private School $north;

    private School $south;

    private School $outsider;

    private School $standalone;

    private User $northAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->group = School::factory()->create(['name' => "St Mary's Group"]);
        $this->north = School::factory()->branchOf($this->group)->create(['name' => "St Mary's North"]);
        $this->south = School::factory()->branchOf($this->group)->create(['name' => "St Mary's South"]);
        // Another group entirely, and a school in no group at all.
        $this->outsider = School::factory()->create(['name' => 'Elsewhere High']);
        $this->standalone = School::factory()->create(['name' => 'Lone Oak School']);

        $this->northAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->north)->create();
    }

    private function adminAt(School $school): User
    {
        return User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
    }

    private function sectionAt(School $school): ClassSection
    {
        $year = AcademicYear::factory()->create(['school_id' => $school->id, 'is_current' => true]);
        $class = SchoolClass::factory()->create(['school_id' => $school->id, 'academic_year_id' => $year->id]);

        return ClassSection::factory()->create(['school_class_id' => $class->id]);
    }

    private function studentAt(School $school, string $name = 'Aarav'): Student
    {
        return Student::factory()->create([
            'school_id' => $school->id,
            'class_section_id' => $this->sectionAt($school)->id,
            'first_name' => $name,
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function studentPayload(School $school, string $admissionNumber = 'ADM-100'): array
    {
        return [
            'school_id' => $school->id,
            'class_section_id' => $this->sectionAt($school)->id,
            'admission_number' => $admissionNumber,
            'first_name' => 'Aarav',
            'last_name' => 'Sharma',
            'guardian_name' => 'Meera Sharma',
        ];
    }

    // -- reading in every direction ---------------------------------------

    public function test_a_branch_admin_reads_upwards_to_the_parent(): void
    {
        $student = $this->studentAt($this->group);

        $this->actingAs($this->northAdmin, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertOk();
    }

    public function test_a_branch_admin_reads_sideways_to_a_sister(): void
    {
        $student = $this->studentAt($this->south);

        $this->actingAs($this->northAdmin, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertOk();
    }

    public function test_a_parent_admin_reads_downwards_to_a_branch(): void
    {
        $student = $this->studentAt($this->north);

        $this->actingAs($this->adminAt($this->group), 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertOk();
    }

    public function test_the_list_can_be_narrowed_to_one_branch(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');

        $names = collect(
            $this->actingAs($this->northAdmin, 'sanctum')
                ->getJson("/api/v1/students?school_id={$this->south->id}")
                ->assertOk()
                ->json('data')
        )->pluck('first_name');

        $this->assertSame(['South'], $names->all());
    }

    // -- the wall around the group -----------------------------------------

    public function test_a_group_admin_cannot_read_another_group(): void
    {
        $student = $this->studentAt($this->outsider);

        $this->actingAs($this->northAdmin, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertForbidden();
    }

    public function test_naming_another_group_in_a_filter_narrows_to_nothing(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->outsider, 'Outsider');

        // Never widens: an id outside the scope is ignored rather than
        // honoured, so the actor sees their own records, not somebody else's.
        $names = collect(
            $this->actingAs($this->northAdmin, 'sanctum')
                ->getJson("/api/v1/students?school_id={$this->outsider->id}")
                ->assertOk()
                ->json('data')
        )->pluck('first_name');

        $this->assertSame(['North'], $names->all());
    }

    public function test_writing_into_another_group_is_refused(): void
    {
        $this->actingAs($this->northAdmin, 'sanctum')
            ->postJson('/api/v1/students', $this->studentPayload($this->outsider))
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_ERROR');
    }

    // -- writing inside the group ------------------------------------------

    public function test_a_branch_admin_admits_a_student_to_a_sister_branch(): void
    {
        $this->actingAs($this->northAdmin, 'sanctum')
            ->postJson('/api/v1/students', $this->studentPayload($this->south))
            ->assertCreated()
            ->assertJsonPath('school_id', $this->south->id);
    }

    public function test_a_branch_admin_edits_a_sister_branch_record(): void
    {
        $student = $this->studentAt($this->south);

        $this->actingAs($this->northAdmin, 'sanctum')
            ->patchJson("/api/v1/students/{$student->id}", ['first_name' => 'Renamed'])
            ->assertOk()
            ->assertJsonPath('first_name', 'Renamed');
    }

    public function test_a_grouped_admin_must_say_which_branch(): void
    {
        // "The group" is not a place a student can be. With more than one
        // school in scope there is no default, so the request has to name one.
        $payload = $this->studentPayload($this->south);
        unset($payload['school_id']);

        $this->actingAs($this->northAdmin, 'sanctum')
            ->postJson('/api/v1/students', $payload)
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    // -- a standalone school is untouched -----------------------------------

    public function test_a_standalone_admin_still_needs_no_school_id(): void
    {
        // The regression guard that matters most: nearly every school on the
        // platform is standalone, and for them this change must be invisible.
        $payload = $this->studentPayload($this->standalone);
        unset($payload['school_id']);

        $this->actingAs($this->adminAt($this->standalone), 'sanctum')
            ->postJson('/api/v1/students', $payload)
            ->assertCreated()
            ->assertJsonPath('school_id', $this->standalone->id);
    }

    public function test_a_standalone_admin_still_sees_only_their_own_school(): void
    {
        $this->studentAt($this->standalone, 'Mine');
        $this->studentAt($this->north, 'Theirs');

        $names = collect(
            $this->actingAs($this->adminAt($this->standalone), 'sanctum')
                ->getJson('/api/v1/students')
                ->assertOk()
                ->json('data')
        )->pluck('first_name');

        $this->assertSame(['Mine'], $names->all());
    }

    public function test_a_standalone_admin_is_refused_the_school_list(): void
    {
        // Nothing to pick between, so nothing to list. Only an admin who
        // genuinely spans branches gets the picker's data.
        $this->actingAs($this->adminAt($this->standalone), 'sanctum')
            ->getJson('/api/v1/schools')
            ->assertForbidden();
    }

    // -- what the client is told --------------------------------------------

    public function test_a_grouped_admin_is_told_to_ask_which_branch(): void
    {
        $this->actingAs($this->northAdmin, 'sanctum')
            ->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('manages_branches', true);
    }

    public function test_a_standalone_admin_is_not(): void
    {
        $this->actingAs($this->adminAt($this->standalone), 'sanctum')
            ->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('manages_branches', false);
    }

    public function test_a_teacher_in_a_group_stays_in_their_own_branch(): void
    {
        // The group is an administrative idea. A teacher at North teaches at
        // North, and gains nothing from the school having sisters.
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($this->north)->create();
        $student = $this->studentAt($this->south);

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertForbidden();
    }

    // -- the dashboard ------------------------------------------------------

    public function test_a_grouped_admin_lands_on_the_group_dashboard(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');

        $cards = collect(
            $this->actingAs($this->northAdmin, 'sanctum')->getJson('/api/v1/dashboard')->assertOk()->json('cards')
        );

        // The group card only appears on the group payload, and its figure is
        // the parent plus both branches.
        $this->assertSame('3', $cards->firstWhere('key', 'branches')['value']);
        $this->assertSame('2', $cards->firstWhere('key', 'students')['value']);
    }

    public function test_a_grouped_admin_can_point_the_dashboard_at_one_branch(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');

        $cards = collect(
            $this->actingAs($this->northAdmin, 'sanctum')
                ->getJson("/api/v1/dashboard?school_id={$this->south->id}")
                ->assertOk()
                ->json('cards')
        );

        $this->assertNull($cards->firstWhere('key', 'branches'));
        $this->assertSame('1', $cards->firstWhere('key', 'students')['value']);
    }

    public function test_a_standalone_admin_still_lands_on_their_own_dashboard(): void
    {
        $this->studentAt($this->standalone, 'Mine');
        $this->studentAt($this->north, 'Theirs');

        $cards = collect(
            $this->actingAs($this->adminAt($this->standalone), 'sanctum')
                ->getJson('/api/v1/dashboard')
                ->assertOk()
                ->json('cards')
        );

        $this->assertNull($cards->firstWhere('key', 'branches'));
        $this->assertSame('1', $cards->firstWhere('key', 'students')['value']);
    }

    // -- the Sub Admin tier --------------------------------------------------

    public function test_a_sub_admin_in_a_group_reaches_the_group_too(): void
    {
        // A Sub Admin is a School Admin with one thing taken away - the
        // ability to manage admin accounts. Scope is not that thing, so they
        // see what their school sees. Recorded because it follows from the
        // decision rather than having been asked for.
        $subAdmin = User::factory()
            ->role(UserRole::SchoolAdmin)
            ->forSchool($this->north)
            ->create(['is_sub_admin' => true]);
        $student = $this->studentAt($this->south);

        $this->actingAs($subAdmin, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertOk();
    }

    public function test_a_sub_admin_still_cannot_create_an_account_anywhere(): void
    {
        $subAdmin = User::factory()
            ->role(UserRole::SchoolAdmin)
            ->forSchool($this->north)
            ->create(['is_sub_admin' => true]);

        $this->actingAs($subAdmin, 'sanctum')
            ->postJson('/api/v1/users', [
                'first_name' => 'Anita',
                'last_name' => 'Rao',
                'email' => 'anita.sub@example.test',
                'password' => 'password123',
                'role' => UserRole::SchoolAdmin->value,
                'school_id' => $this->south->id,
            ])
            ->assertForbidden();
    }

    public function test_a_head_admin_onboards_a_sub_admin_into_a_sister_branch(): void
    {
        $this->actingAs($this->northAdmin, 'sanctum')
            ->postJson('/api/v1/users', [
                'first_name' => 'Anita',
                'last_name' => 'Rao',
                'email' => 'anita.south@example.test',
                'password' => 'password123',
                'role' => UserRole::SchoolAdmin->value,
                'school_id' => $this->south->id,
            ])
            ->assertCreated()
            ->assertJsonPath('school_id', $this->south->id);
    }

    // -- still not a platform role ------------------------------------------

    public function test_a_grouped_admin_still_cannot_create_a_school(): void
    {
        $this->actingAs($this->northAdmin, 'sanctum')
            ->postJson('/api/v1/schools', [
                'name' => 'St Mary\'s West',
                'email' => 'west@stmarys.test',
                'currency_code' => 'INR',
                'timezone' => 'Asia/Kolkata',
            ])
            ->assertForbidden();
    }

    public function test_a_grouped_admin_still_cannot_see_payments(): void
    {
        $this->actingAs($this->northAdmin, 'sanctum')
            ->getJson('/api/v1/payments')
            ->assertForbidden();
    }
}
