<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * School groups: several branches under one parent.
 *
 * The rule worth defending here is that a group is exactly one level deep.
 * It is cheap to enforce now and expensive to unpick once real schools are
 * linked - a three-deep tree means deciding, after the fact, which group
 * somebody's records belonged to all along.
 */
class SchoolGroupTest extends TestCase
{
    use RefreshDatabase;

    private function superAdmin(): User
    {
        return User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'St Mary\'s North',
            'email' => 'north@stmarys.test',
            'phone' => '+91 9876543210',
            'address' => '1 North Road',
            'city' => 'Pune',
            'state' => 'MH',
            'country' => 'India',
            'postal_code' => '411001',
            'currency_code' => 'INR',
            'timezone' => 'Asia/Kolkata',
        ], $overrides);
    }

    // ── making a branch ─────────────────────────────────────────────────

    public function test_a_school_is_standalone_unless_it_names_a_parent(): void
    {
        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/schools', $this->payload())
            ->assertCreated()
            ->assertJsonPath('parent_school_id', null);
    }

    public function test_a_school_can_be_onboarded_as_a_branch(): void
    {
        $group = School::factory()->create(['name' => 'St Mary\'s Group']);

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/schools', $this->payload(['parent_school_id' => $group->id]))
            ->assertCreated()
            ->assertJsonPath('parent_school_id', $group->id);

        $this->assertSame(1, $group->branches()->count());
    }

    public function test_an_existing_school_can_be_moved_into_a_group(): void
    {
        $group = School::factory()->create();
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->patchJson("/api/v1/schools/{$school->id}", ['parent_school_id' => $group->id])
            ->assertOk()
            ->assertJsonPath('parent_school_id', $group->id);
    }

    public function test_a_branch_can_be_taken_back_out_of_its_group(): void
    {
        $group = School::factory()->create();
        $branch = School::factory()->branchOf($group)->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->patchJson("/api/v1/schools/{$branch->id}", ['parent_school_id' => null])
            ->assertOk()
            ->assertJsonPath('parent_school_id', null);
    }

    // ── one level deep, and no cycles ───────────────────────────────────

    public function test_a_branch_cannot_itself_be_a_parent(): void
    {
        $group = School::factory()->create();
        $branch = School::factory()->branchOf($group)->create(['name' => 'St Mary\'s North']);

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/schools', $this->payload(['parent_school_id' => $branch->id]))
            ->assertStatus(422)
            ->assertJsonPath(
                'details.errors.parent_school_id.0',
                '"St Mary\'s North" is itself a branch. A group is one level deep: pick its parent instead.',
            );
    }

    public function test_a_parent_cannot_become_a_branch_of_something_else(): void
    {
        $group = School::factory()->create(['name' => 'St Mary\'s Group']);
        School::factory()->branchOf($group)->create();
        $other = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->patchJson("/api/v1/schools/{$group->id}", ['parent_school_id' => $other->id])
            ->assertStatus(422)
            ->assertJsonPath(
                'details.errors.parent_school_id.0',
                '"St Mary\'s Group" has branches of its own, so it cannot become a branch of another school.',
            );
    }

    public function test_a_school_cannot_be_a_branch_of_itself(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->patchJson("/api/v1/schools/{$school->id}", ['parent_school_id' => $school->id])
            ->assertStatus(422)
            ->assertJsonPath('details.errors.parent_school_id.0', 'A school cannot be a branch of itself.');
    }

    public function test_a_parent_that_does_not_exist_is_refused(): void
    {
        $this->actingAs($this->superAdmin(), 'sanctum')
            ->postJson('/api/v1/schools', $this->payload(['parent_school_id' => 9999]))
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['parent_school_id']]]);
    }

    // ── reading a group back ────────────────────────────────────────────

    public function test_the_school_list_names_the_parent_and_counts_the_branches(): void
    {
        $group = School::factory()->create(['name' => 'St Mary\'s Group']);
        School::factory()->branchOf($group)->create(['name' => 'St Mary\'s North']);
        School::factory()->branchOf($group)->create(['name' => 'St Mary\'s South']);

        $response = $this->actingAs($this->superAdmin(), 'sanctum')->getJson('/api/v1/schools');

        $response->assertOk();

        $byName = collect($response->json('data'))->keyBy('name');

        $this->assertSame(2, $byName['St Mary\'s Group']['branch_count']);
        $this->assertNull($byName['St Mary\'s Group']['parent_school_id']);
        $this->assertSame($group->id, $byName['St Mary\'s North']['parent_school_id']);
        $this->assertSame('St Mary\'s Group', $byName['St Mary\'s North']['parent_school_name']);
        $this->assertSame(0, $byName['St Mary\'s North']['branch_count']);
    }

    public function test_the_school_list_does_not_fire_a_query_per_row_for_the_parent(): void
    {
        $group = School::factory()->create();
        School::factory()->count(5)->branchOf($group)->create();

        \DB::enableQueryLog();
        $this->actingAs($this->superAdmin(), 'sanctum')->getJson('/api/v1/schools')->assertOk();
        $queries = count(\DB::getQueryLog());
        \DB::disableQueryLog();

        // page + count + parents + branch counts, and nothing per row.
        $this->assertLessThan(10, $queries, "The school list ran {$queries} queries.");
    }

    // ── the group itself ────────────────────────────────────────────────

    public function test_a_standalone_school_is_a_group_of_one(): void
    {
        $school = School::factory()->create();

        $this->assertSame([$school->id], $school->groupSchoolIds());
        $this->assertFalse($school->isBranch());
    }

    public function test_a_parent_sees_itself_and_every_branch(): void
    {
        $group = School::factory()->create();
        $north = School::factory()->branchOf($group)->create();
        $south = School::factory()->branchOf($group)->create();
        School::factory()->create(); // another group entirely

        $this->assertEqualsCanonicalizing([$group->id, $north->id, $south->id], $group->groupSchoolIds());
    }

    public function test_a_branch_sees_the_same_group_as_its_parent(): void
    {
        $group = School::factory()->create();
        $north = School::factory()->branchOf($group)->create();
        $south = School::factory()->branchOf($group)->create();

        // Whichever branch you ask, the group is the same set - siblings
        // included.
        $this->assertEqualsCanonicalizing($group->groupSchoolIds(), $north->groupSchoolIds());
        $this->assertContains($south->id, $north->groupSchoolIds());
        $this->assertTrue($north->isBranch());
    }

    public function test_one_group_never_reaches_into_another(): void
    {
        $ours = School::factory()->create();
        $ourBranch = School::factory()->branchOf($ours)->create();
        $theirs = School::factory()->create();
        $theirBranch = School::factory()->branchOf($theirs)->create();

        $this->assertNotContains($theirs->id, $ourBranch->groupSchoolIds());
        $this->assertNotContains($theirBranch->id, $ourBranch->groupSchoolIds());
    }

    // ── what a deleted parent leaves behind ─────────────────────────────

    public function test_deleting_a_parent_leaves_its_branches_standing(): void
    {
        // Cascading would delete a whole group's students because somebody
        // removed the head office row.
        $group = School::factory()->create();
        $branch = School::factory()->branchOf($group)->create();

        $group->delete();

        $this->assertDatabaseHas('schools', ['id' => $branch->id, 'parent_school_id' => null]);
    }

    // ── who may do any of this ──────────────────────────────────────────

    public function test_a_school_admin_cannot_move_their_school_into_a_group(): void
    {
        $school = School::factory()->create();
        $group = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        // School onboarding is a platform action, not a school one.
        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/schools/{$school->id}", ['parent_school_id' => $group->id])
            ->assertForbidden();

        $this->assertNull($school->refresh()->parent_school_id);
    }
}
