<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Period;
use App\Models\School;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PeriodManagementTest extends TestCase
{
    use RefreshDatabase;

    // ── create ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_create_a_period(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/periods', [
            'period_number' => 1,
            'start_time' => '08:30',
            'end_time' => '09:15',
        ]);

        $response->assertCreated()
            ->assertJsonPath('period_number', 1)
            ->assertJsonPath('start_time', '08:30')
            ->assertJsonPath('end_time', '09:15');
        $this->assertDatabaseHas('periods', ['school_id' => $school->id, 'period_number' => 1]);
    }

    public function test_a_super_admin_must_specify_a_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/periods', [
            'period_number' => 1,
            'start_time' => '08:30',
            'end_time' => '09:15',
        ])->assertUnprocessable();
    }

    public function test_a_teacher_cannot_create_a_period(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/periods', [
            'period_number' => 1,
            'start_time' => '08:30',
            'end_time' => '09:15',
        ])->assertForbidden();
    }

    public function test_period_number_must_be_unique_per_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        Period::factory()->forSchool($school)->number(1)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/periods', [
            'period_number' => 1,
            'start_time' => '09:20',
            'end_time' => '10:05',
        ])->assertUnprocessable();
    }

    public function test_the_same_period_number_is_allowed_in_a_different_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        Period::factory()->forSchool($schoolA)->number(1)->create();
        $adminB = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolB)->create();

        $this->actingAs($adminB, 'sanctum')->postJson('/api/v1/periods', [
            'period_number' => 1,
            'start_time' => '08:30',
            'end_time' => '09:15',
        ])->assertCreated();
    }

    public function test_end_time_must_be_after_start_time(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/periods', [
            'period_number' => 1,
            'start_time' => '09:15',
            'end_time' => '08:30',
        ])->assertUnprocessable();
    }

    // ── update ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_update_a_period(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $period = Period::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/periods/{$period->id}", ['start_time' => '08:00'])
            ->assertOk()
            ->assertJsonPath('start_time', '08:00');
    }

    public function test_a_school_admin_cannot_update_another_schools_period(): void
    {
        $period = Period::factory()->create();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')->patchJson("/api/v1/periods/{$period->id}", ['start_time' => '08:00'])
            ->assertForbidden();
    }

    // ── delete ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_delete_an_unused_period(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $period = Period::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/periods/{$period->id}")->assertNoContent();
        $this->assertDatabaseMissing('periods', ['id' => $period->id]);
    }

    public function test_deleting_a_period_with_timetable_entries_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $period = Period::factory()->forSchool($school)->create();
        TimetableEntry::factory()->forPeriod($period)->create(['school_id' => $school->id]);

        $response = $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/periods/{$period->id}");

        $response->assertConflict()->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
        $this->assertDatabaseHas('periods', ['id' => $period->id]);
    }

    public function test_a_school_admin_cannot_delete_another_schools_period(): void
    {
        $period = Period::factory()->create();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')->deleteJson("/api/v1/periods/{$period->id}")->assertForbidden();
        $this->assertDatabaseHas('periods', ['id' => $period->id]);
    }

    public function test_a_teacher_cannot_delete_a_period(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $period = Period::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/periods/{$period->id}")->assertForbidden();
    }

    // ── list ─────────────────────────────────────────────────────────────

    public function test_a_school_admin_only_sees_their_own_schools_periods(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        Period::factory()->forSchool($schoolA)->count(2)->create();
        Period::factory()->forSchool($schoolB)->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();

        $response = $this->actingAs($adminA, 'sanctum')->getJson('/api/v1/periods');

        $response->assertOk();
        $this->assertCount(2, $response->json());
    }

    public function test_a_super_admin_can_list_periods_for_a_specific_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        Period::factory()->forSchool($schoolA)->count(2)->create();
        Period::factory()->forSchool($schoolB)->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson("/api/v1/periods?school_id={$schoolA->id}");

        $response->assertOk();
        $this->assertCount(2, $response->json());
    }
}
