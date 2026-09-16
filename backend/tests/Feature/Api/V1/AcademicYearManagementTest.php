<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AcademicYearManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_school_admin_can_create_an_academic_year_for_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/academic-years', [
            'name' => '2026-27',
            'start_date' => '2026-04-01',
            'end_date' => '2027-03-31',
            'is_current' => true,
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('name', '2026-27')
            ->assertJsonPath('is_current', true);
    }

    public function test_a_school_admin_cannot_plant_an_academic_year_into_another_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/academic-years', [
            'school_id' => $otherSchool->id,
            'name' => '2026-27',
            'start_date' => '2026-04-01',
            'end_date' => '2027-03-31',
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $ownSchool->id);
    }

    public function test_a_school_admin_only_sees_academic_years_from_their_own_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        AcademicYear::factory()->forSchool($schoolA)->count(2)->create();
        AcademicYear::factory()->forSchool($schoolB)->count(3)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/academic-years');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_cannot_view_an_academic_year_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $yearB = AcademicYear::factory()->forSchool($schoolB)->create();

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/v1/academic-years/{$yearB->id}")
            ->assertForbidden();
    }

    public function test_a_teacher_can_view_but_not_create_an_academic_year(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/academic-years/{$year->id}")
            ->assertOk();

        $this->actingAs($teacher, 'sanctum')
            ->postJson('/api/v1/academic-years', [
                'name' => '2026-27',
                'start_date' => '2026-04-01',
                'end_date' => '2027-03-31',
            ])
            ->assertForbidden();
    }

    public function test_creating_an_academic_year_validates_the_date_range(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/academic-years', [
                'name' => '2026-27',
                'start_date' => '2027-03-31',
                'end_date' => '2026-04-01',
            ])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['end_date']]]);
    }

    public function test_setting_a_new_current_year_unsets_the_previous_one(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $oldCurrent = AcademicYear::factory()->forSchool($school)->current()->create();
        $newYear = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/academic-years/{$newYear->id}/set-current")
            ->assertOk()
            ->assertJsonPath('is_current', true);

        $this->assertFalse($oldCurrent->fresh()->is_current);
    }

    public function test_a_super_admin_is_not_restricted_by_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        AcademicYear::factory()->forSchool($schoolA)->create();
        AcademicYear::factory()->forSchool($schoolB)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/academic-years');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_deleting_an_academic_year_that_has_classes_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();
        SchoolClass::factory()->forAcademicYear($year)->create();

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/v1/academic-years/{$year->id}")
            ->assertStatus(409)
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
    }

    public function test_deleting_an_empty_academic_year_succeeds(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/academic-years/{$year->id}")->assertNoContent();
        $this->assertDatabaseMissing('academic_years', ['id' => $year->id]);
    }

    public function test_a_school_admin_cannot_delete_an_academic_year_from_another_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();
        $year = AcademicYear::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/academic-years/{$year->id}")->assertForbidden();
    }

    public function test_a_teacher_cannot_delete_an_academic_year(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/academic-years/{$year->id}")->assertForbidden();
    }

    public function test_a_school_admin_can_update_an_academic_years_name(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/academic-years/{$year->id}", ['name' => 'Renamed'])
            ->assertOk()
            ->assertJsonPath('name', 'Renamed');
    }

    public function test_a_school_admin_cannot_update_an_academic_year_from_another_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();
        $year = AcademicYear::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/academic-years/{$year->id}", ['name' => 'Renamed'])
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_update_an_academic_year(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->patchJson("/api/v1/academic-years/{$year->id}", ['name' => 'Renamed'])
            ->assertForbidden();
    }

    public function test_a_school_admin_cannot_set_current_an_academic_year_from_another_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();
        $year = AcademicYear::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/academic-years/{$year->id}/set-current")
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_set_current_an_academic_year(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->patchJson("/api/v1/academic-years/{$year->id}/set-current")
            ->assertForbidden();
    }

    public function test_an_academic_year_name_exceeding_the_max_length_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/academic-years', [
            'name' => str_repeat('a', 51),
            'start_date' => '2026-04-01',
            'end_date' => '2027-03-31',
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['name']]]);
    }

    public function test_a_created_year_reports_is_current_rather_than_null(): void
    {
        // `is_current` is NOT NULL with a default of false, so the API must
        // never answer null for it. It used to, whenever a request omitted the
        // field: the response described the half-filled model handed to
        // create() rather than the stored row. The Flutter client reads it as
        // a plain bool and would have thrown on the null - it only escaped
        // because that client always sends the field.
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/academic-years', [
                'name' => '2030-31',
                'start_date' => '2030-04-01',
                'end_date' => '2031-03-31',
            ])
            ->assertCreated()
            ->assertJsonPath('is_current', false);
    }
}
