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
 * A Group Admin: reads every branch in its group, writes into whichever it
 * names, and reaches nothing outside.
 *
 * The DENY tests here matter more than the ALLOW ones. This is the first role
 * that legitimately sees more than one school, so it is the first chance for
 * one school's records to reach somebody who should not have them.
 */
class GroupAdminTest extends TestCase
{
    use RefreshDatabase;

    private School $group;

    private School $north;

    private School $south;

    private School $outsider;

    private User $groupAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->group = School::factory()->create(['name' => "St Mary's Group"]);
        $this->north = School::factory()->branchOf($this->group)->create(['name' => "St Mary's North"]);
        $this->south = School::factory()->branchOf($this->group)->create(['name' => "St Mary's South"]);
        // A completely unrelated school, with its own group.
        $this->outsider = School::factory()->create(['name' => 'Elsewhere High']);

        $this->groupAdmin = User::factory()->role(UserRole::GroupAdmin)->forSchool($this->group)->create();
    }

    private function studentAt(School $school, string $name = 'Aarav'): Student
    {
        $year = AcademicYear::factory()->create(['school_id' => $school->id, 'is_current' => true]);
        $class = SchoolClass::factory()->create(['school_id' => $school->id, 'academic_year_id' => $year->id]);
        $section = ClassSection::factory()->create(['school_class_id' => $class->id]);

        return Student::factory()->create([
            'school_id' => $school->id,
            'class_section_id' => $section->id,
            'first_name' => $name,
        ]);
    }

    private function asGroupAdmin(): self
    {
        $this->actingAs($this->groupAdmin, 'sanctum');

        return $this;
    }

    /**
     * @return array<string, mixed>
     */
    private function studentPayload(School $school): array
    {
        $year = AcademicYear::factory()->create(['school_id' => $school->id, 'is_current' => true]);
        $class = SchoolClass::factory()->create(['school_id' => $school->id, 'academic_year_id' => $year->id]);
        $section = ClassSection::factory()->create(['school_class_id' => $class->id]);

        return [
            'school_id' => $school->id,
            'class_section_id' => $section->id,
            'admission_number' => 'ADM-001',
            'first_name' => 'Aarav',
            'last_name' => 'Sharma',
            'guardian_name' => 'Meera Sharma',
        ];
    }

    // -- reading across the group ----------------------------------------

    public function test_a_group_admin_reads_a_sister_branch_student(): void
    {
        $student = $this->studentAt($this->north);

        $this->asGroupAdmin()
            ->getJson("/api/v1/students/{$student->id}")
            ->assertOk()
            ->assertJsonPath('id', $student->id);
    }

    public function test_a_group_admin_cannot_read_a_student_outside_the_group(): void
    {
        $student = $this->studentAt($this->outsider);

        $this->asGroupAdmin()->getJson("/api/v1/students/{$student->id}")->assertForbidden();
    }

    public function test_the_student_list_spans_every_branch_and_stops_there(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');
        $this->studentAt($this->outsider, 'Outsider');

        $names = collect($this->asGroupAdmin()->getJson('/api/v1/students')->assertOk()->json('data'))
            ->pluck('first_name');

        $this->assertEqualsCanonicalizing(['North', 'South'], $names->all());
    }

    public function test_the_list_can_be_narrowed_to_one_branch(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');

        $names = collect(
            $this->asGroupAdmin()->getJson("/api/v1/students?school_id={$this->north->id}")->assertOk()->json('data')
        )->pluck('first_name');

        $this->assertSame(['North'], $names->all());
    }

    public function test_asking_for_a_school_outside_the_group_shows_the_group_not_the_school(): void
    {
        // The filter narrows within the scope; it can never widen past it.
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->outsider, 'Outsider');

        $names = collect(
            $this->asGroupAdmin()->getJson("/api/v1/students?school_id={$this->outsider->id}")->assertOk()->json('data')
        )->pluck('first_name');

        $this->assertSame(['North'], $names->all());
        $this->assertNotContains('Outsider', $names->all());
    }

    // -- writing into a branch -------------------------------------------

    public function test_a_group_admin_admits_a_student_to_a_branch_it_names(): void
    {
        $this->asGroupAdmin()
            ->postJson('/api/v1/students', $this->studentPayload($this->north))
            ->assertCreated()
            ->assertJsonPath('school_id', $this->north->id);
    }

    public function test_a_group_admin_must_say_which_branch(): void
    {
        // Unlike a School Admin, "my school" is ambiguous for them.
        $payload = $this->studentPayload($this->north);
        unset($payload['school_id']);

        $this->asGroupAdmin()
            ->postJson('/api/v1/students', $payload)
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_a_group_admin_cannot_write_into_a_school_outside_the_group(): void
    {
        $this->asGroupAdmin()
            ->postJson('/api/v1/students', $this->studentPayload($this->outsider))
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);

        $this->assertSame(0, Student::query()->where('school_id', $this->outsider->id)->count());
    }

    public function test_a_group_admin_edits_a_sister_branch_record(): void
    {
        $student = $this->studentAt($this->south);

        $this->asGroupAdmin()
            ->patchJson("/api/v1/students/{$student->id}", ['first_name' => 'Ishaan'])
            ->assertOk()
            ->assertJsonPath('first_name', 'Ishaan');
    }

    public function test_a_group_admin_cannot_edit_a_record_outside_the_group(): void
    {
        $student = $this->studentAt($this->outsider, 'Untouched');

        $this->asGroupAdmin()
            ->patchJson("/api/v1/students/{$student->id}", ['first_name' => 'Changed'])
            ->assertForbidden();

        $this->assertSame('Untouched', $student->refresh()->first_name);
    }

    // -- what a group admin is not ---------------------------------------

    public function test_a_group_admin_cannot_onboard_a_school(): void
    {
        // Onboarding is a platform action, not a school one.
        $this->asGroupAdmin()->postJson('/api/v1/schools', [
            'name' => 'A New School',
            'email' => 'new@example.test',
            'phone' => '+91 9876543210',
            'address' => '1 Road',
            'city' => 'Pune',
            'state' => 'MH',
            'country' => 'India',
            'postal_code' => '411001',
            'currency_code' => 'INR',
            'timezone' => 'Asia/Kolkata',
        ])->assertForbidden();
    }

    public function test_a_group_admin_cannot_move_a_branch_between_groups(): void
    {
        $this->asGroupAdmin()
            ->patchJson("/api/v1/schools/{$this->north->id}", ['parent_school_id' => $this->outsider->id])
            ->assertForbidden();

        $this->assertSame($this->group->id, $this->north->refresh()->parent_school_id);
    }

    public function test_a_group_admin_cannot_record_a_payment(): void
    {
        // Payments are what a school owes the platform - Super Admin only.
        $this->asGroupAdmin()->getJson('/api/v1/payments')->assertForbidden();
    }

    public function test_a_group_admin_does_not_apply_for_leave(): void
    {
        // They have no employment record at any branch; leave belongs to the
        // branch that employs somebody.
        $this->asGroupAdmin()->postJson('/api/v1/leaves', [
            'leave_type' => 'casual',
            'start_date' => '2026-10-01',
            'end_date' => '2026-10-01',
            'reason' => 'Testing',
        ])->assertForbidden();
    }

    // -- the regression the other design would have introduced ------------

    public function test_a_school_admin_at_the_parent_still_cannot_see_a_branch(): void
    {
        // This is the whole reason GROUP_ADMIN exists as its own role: if a
        // parent's School Admin could see downwards, every existing
        // permission would have quietly changed meaning.
        $parentAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->group)->create();
        $student = $this->studentAt($this->north);

        $this->actingAs($parentAdmin, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertForbidden();
    }

    public function test_a_school_admin_at_a_branch_cannot_see_its_sister(): void
    {
        $northAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->north)->create();
        $student = $this->studentAt($this->south);

        $this->actingAs($northAdmin, 'sanctum')
            ->getJson("/api/v1/students/{$student->id}")
            ->assertForbidden();
    }

    public function test_a_branch_admins_list_is_still_only_their_own_branch(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');
        $northAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->north)->create();

        $names = collect(
            $this->actingAs($northAdmin, 'sanctum')->getJson('/api/v1/students')->assertOk()->json('data')
        )->pluck('first_name');

        $this->assertSame(['North'], $names->all());
    }

    // -- users ------------------------------------------------------------

    public function test_the_user_list_spans_the_group_and_stops_there(): void
    {
        $mine = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->north)->create();
        $theirs = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->outsider)->create();

        $ids = collect($this->asGroupAdmin()->getJson('/api/v1/users')->assertOk()->json('data'))->pluck('id');

        $this->assertContains($mine->id, $ids->all());
        $this->assertNotContains($theirs->id, $ids->all());
    }

    public function test_a_group_admin_onboards_an_admin_into_a_branch(): void
    {
        $this->asGroupAdmin()->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Nair',
            'email' => 'priya.branch@example.test',
            'password' => 'password123',
            'role' => UserRole::SchoolAdmin->value,
            'school_id' => $this->south->id,
        ])->assertCreated()->assertJsonPath('school_id', $this->south->id);
    }

    public function test_a_group_admin_cannot_onboard_into_a_school_outside_the_group(): void
    {
        $this->asGroupAdmin()->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Nair',
            'email' => 'priya.outside@example.test',
            'password' => 'password123',
            'role' => UserRole::SchoolAdmin->value,
            'school_id' => $this->outsider->id,
        ])->assertStatus(422);

        $this->assertNull(User::query()->where('email', 'priya.outside@example.test')->first());
    }

    public function test_a_group_admin_cannot_make_another_group_admin(): void
    {
        // Only a Super Admin hands out the group-level role.
        $this->asGroupAdmin()->postJson('/api/v1/users', [
            'first_name' => 'Rahul',
            'last_name' => 'Verma',
            'email' => 'rahul.group@example.test',
            'password' => 'password123',
            'role' => UserRole::GroupAdmin->value,
            'school_id' => $this->group->id,
        ])->assertStatus(422);
    }

    public function test_a_school_admin_cannot_manage_a_group_admin(): void
    {
        // A Group Admin is admin-tier, and sits above a branch's admin.
        $branchAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->group)->create();

        $this->actingAs($branchAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$this->groupAdmin->id}", ['first_name' => 'Renamed'])
            ->assertForbidden();
    }

    // -- onboarding the role itself ---------------------------------------

    public function test_a_super_admin_onboards_a_group_admin_at_the_parent(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Anita',
            'last_name' => 'Rao',
            'email' => 'anita@example.test',
            'password' => 'password123',
            'role' => UserRole::GroupAdmin->value,
            'school_id' => $this->group->id,
        ])->assertCreated()->assertJsonPath('role', UserRole::GroupAdmin->value);
    }

    public function test_a_group_admin_cannot_be_attached_to_a_branch(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Anita',
            'last_name' => 'Rao',
            'email' => 'anita.branch@example.test',
            'password' => 'password123',
            'role' => UserRole::GroupAdmin->value,
            'school_id' => $this->north->id,
        ])
            ->assertStatus(422)
            ->assertJsonPath(
                'details.errors.school_id.0',
                '"St Mary\'s North" is a branch. A Group Admin belongs to the school the branches sit under.',
            );
    }

    // -- the dashboard -----------------------------------------------------

    public function test_the_dashboard_rolls_the_whole_group_up(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');
        $this->studentAt($this->outsider, 'Outsider');

        $cards = collect($this->asGroupAdmin()->getJson('/api/v1/dashboard')->assertOk()->json('cards'))
            ->keyBy('key');

        $this->assertSame('3', $cards['branches']['value'], 'the parent and its two branches');
        // The outsider's student is not in the group.
        $this->assertSame('2', $cards['students']['value']);
    }

    public function test_the_dashboard_can_be_pointed_at_one_branch(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->south, 'South');

        $cards = collect(
            $this->asGroupAdmin()->getJson("/api/v1/dashboard?school_id={$this->north->id}")->assertOk()->json('cards')
        )->keyBy('key');

        $this->assertSame('1', $cards['students']['value']);
    }

    public function test_the_dashboard_will_not_be_pointed_outside_the_group(): void
    {
        $this->studentAt($this->north, 'North');
        $this->studentAt($this->outsider, 'Outsider');

        $cards = collect(
            $this->asGroupAdmin()->getJson("/api/v1/dashboard?school_id={$this->outsider->id}")
                ->assertOk()
                ->json('cards')
        )->keyBy('key');

        // Fell back to the group, not the school they asked for.
        $this->assertSame('3', $cards['branches']['value']);
    }

    // -- reports and settings ---------------------------------------------

    public function test_a_group_admin_reports_on_a_branch(): void
    {
        $this->asGroupAdmin()
            ->getJson("/api/v1/reports/student-attendance?school_id={$this->north->id}&from=2026-09-01&to=2026-09-07")
            ->assertOk();
    }

    public function test_asking_to_report_outside_the_group_reports_on_the_group(): void
    {
        // Ignored, not refused - the same as every other school filter in the
        // app. What must never happen is the outsider's figures coming back.
        $response = $this->asGroupAdmin()
            ->getJson("/api/v1/reports/student-attendance?school_id={$this->outsider->id}&from=2026-09-01&to=2026-09-07")
            ->assertOk();

        $this->assertTrue($response->json('group'));
        $this->assertEqualsCanonicalizing(
            [$this->group->id, $this->north->id, $this->south->id],
            array_column($response->json('branches'), 'school_id'),
        );
    }

    public function test_a_group_admin_configures_a_branch_but_not_an_outsider(): void
    {
        $this->asGroupAdmin()
            ->getJson("/api/v1/communication/settings?school_id={$this->south->id}")
            ->assertOk();

        $this->asGroupAdmin()
            ->getJson("/api/v1/communication/settings?school_id={$this->outsider->id}")
            ->assertForbidden();
    }

    public function test_the_school_list_is_the_group_and_nothing_else(): void
    {
        $names = collect($this->asGroupAdmin()->getJson('/api/v1/schools')->assertOk()->json('data'))
            ->pluck('name');

        $this->assertEqualsCanonicalizing(
            ["St Mary's Group", "St Mary's North", "St Mary's South"],
            $names->all(),
        );
        $this->assertNotContains('Elsewhere High', $names->all());
    }

    public function test_a_school_admin_still_cannot_list_schools_at_all(): void
    {
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->north)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/schools')->assertForbidden();
    }

    // -- a group of one ----------------------------------------------------

    public function test_a_group_admin_of_a_school_with_no_branches_sees_only_it(): void
    {
        $lone = School::factory()->create();
        $admin = User::factory()->role(UserRole::GroupAdmin)->forSchool($lone)->create();
        $this->studentAt($lone, 'Only');
        $this->studentAt($this->north, 'NotMine');

        $names = collect(
            $this->actingAs($admin, 'sanctum')->getJson('/api/v1/students')->assertOk()->json('data')
        )->pluck('first_name');

        $this->assertSame(['Only'], $names->all());
    }

    public function test_a_group_admin_with_no_school_at_all_sees_nothing(): void
    {
        // Should not exist - validation requires a school - but if one is
        // ever made by hand, it must fail closed rather than open.
        $orphan = User::factory()->role(UserRole::GroupAdmin)->create(['school_id' => null]);
        $this->studentAt($this->north);

        $this->actingAs($orphan, 'sanctum')
            ->getJson('/api/v1/students')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }
}
