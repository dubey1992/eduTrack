<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\School;
use App\Models\StaffAttendance;
use App\Models\StaffProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StaffAttendanceManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: Department, 2: User, 3: array<int, StaffProfile>}
     */
    private function makeDepartmentWithHodAndStaff(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hod)->create();
        $staff = collect(range(1, 3))->map(function () use ($school, $department) {
            $user = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

            return StaffProfile::factory()->forUser($user)->forDepartment($department)->create();
        });

        return [$school, $department, $hod, $staff];
    }

    private function recordsFor(iterable $staff, string $status = 'present'): array
    {
        return collect($staff)->map(fn (StaffProfile $s) => ['staff_profile_id' => $s->id, 'status' => $status])->all();
    }

    // ── register ─────────────────────────────────────────────────────────

    public function test_a_school_admin_can_view_their_schools_staff_register(): void
    {
        [$school] = $this->makeDepartmentWithHodAndStaff();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/staff-attendance/register?date='.now()->toDateString());

        $response->assertOk()
            ->assertJsonPath('submitted', false)
            ->assertJsonCount(3, 'staff');
    }

    public function test_an_hod_only_sees_staff_in_the_department_they_head(): void
    {
        [$school, , $hod] = $this->makeDepartmentWithHodAndStaff();
        // A second department in the same school, headed by someone else.
        $otherDepartment = Department::factory()->forSchool($school)->create();
        $outsiderUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        StaffProfile::factory()->forUser($outsiderUser)->forDepartment($otherDepartment)->create();

        $response = $this->actingAs($hod, 'sanctum')
            ->getJson('/api/v1/staff-attendance/register?date='.now()->toDateString());

        $response->assertOk()->assertJsonCount(3, 'staff');
    }

    public function test_an_hod_cannot_see_another_schools_staff(): void
    {
        [, , $hod] = $this->makeDepartmentWithHodAndStaff();
        $otherSchool = School::factory()->create();

        $this->actingAs($hod, 'sanctum')
            ->getJson("/api/v1/staff-attendance/register?school_id={$otherSchool->id}&date=".now()->toDateString())
            // school_id is ignored/derived for a non-SUPER_ADMIN, never
            // trusted - still resolves to the HOD's own 3 staff, not
            // $otherSchool's (which would be 0, since it has none).
            ->assertOk()
            ->assertJsonCount(3, 'staff');
    }

    public function test_a_school_admin_cannot_view_a_register_from_another_school(): void
    {
        [$school] = $this->makeDepartmentWithHodAndStaff();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')
            ->getJson('/api/v1/staff-attendance/register?date='.now()->toDateString())
            // Resolves to the actor's own (empty) school, not $school -
            // still 200, but $school's 3 staff never leak into the response.
            ->assertOk()
            ->assertJsonCount(0, 'staff');
    }

    public function test_a_super_admin_must_specify_a_school(): void
    {
        $this->makeDepartmentWithHodAndStaff();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/v1/staff-attendance/register?date='.now()->toDateString())
            ->assertUnprocessable();
    }

    public function test_a_teacher_cannot_view_staff_attendance(): void
    {
        [$school] = $this->makeDepartmentWithHodAndStaff();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->getJson('/api/v1/staff-attendance/register?date='.now()->toDateString())
            ->assertForbidden();
    }

    // ── submit / update ─────────────────────────────────────────────────

    public function test_a_school_admin_can_submit_staff_attendance(): void
    {
        [$school, , , $staff] = $this->makeDepartmentWithHodAndStaff();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => now()->toDateString(),
            'records' => $this->recordsFor($staff),
        ]);

        $response->assertCreated()->assertJsonPath('submitted', true);
        $this->assertDatabaseCount('staff_attendances', 3);
    }

    public function test_submitting_the_same_day_twice_is_rejected(): void
    {
        [$school, , , $staff] = $this->makeDepartmentWithHodAndStaff();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $payload = ['attendance_date' => now()->toDateString(), 'records' => $this->recordsFor($staff)];

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff-attendance', $payload)->assertCreated();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff-attendance', $payload)
            ->assertConflict()
            ->assertJsonPath('code', 'ATTENDANCE_ALREADY_SUBMITTED');
    }

    public function test_updating_corrects_an_already_submitted_day(): void
    {
        [$school, , , $staff] = $this->makeDepartmentWithHodAndStaff();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => now()->toDateString(),
            'records' => $this->recordsFor($staff),
        ])->assertCreated();

        $response = $this->actingAs($admin, 'sanctum')->patchJson('/api/v1/staff-attendance', [
            'attendance_date' => now()->toDateString(),
            'records' => [
                ['staff_profile_id' => $staff[0]->id, 'status' => 'half_day', 'check_in' => '08:05', 'check_out' => '12:30'],
                ...$this->recordsFor($staff->slice(1)),
            ],
        ]);

        $response->assertOk();
        $this->assertDatabaseHas('staff_attendances', [
            'staff_profile_id' => $staff[0]->id,
            'status' => 'half_day',
            'check_in' => '08:05:00',
            'check_out' => '12:30:00',
        ]);
    }

    public function test_an_hod_cannot_submit_attendance_for_a_staff_member_outside_their_department(): void
    {
        [$school, , $hod] = $this->makeDepartmentWithHodAndStaff();
        $otherDepartment = Department::factory()->forSchool($school)->create();
        $outsiderUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $outsider = StaffProfile::factory()->forUser($outsiderUser)->forDepartment($otherDepartment)->create();

        $this->actingAs($hod, 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => now()->toDateString(),
            'records' => [['staff_profile_id' => $outsider->id, 'status' => 'present']],
        ])->assertUnprocessable();
    }

    public function test_a_teacher_cannot_submit_staff_attendance(): void
    {
        [$school, , , $staff] = $this->makeDepartmentWithHodAndStaff();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => now()->toDateString(),
            'records' => $this->recordsFor($staff),
        ])->assertForbidden();
    }

    public function test_marking_a_future_date_is_rejected(): void
    {
        [$school, , , $staff] = $this->makeDepartmentWithHodAndStaff();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff-attendance', [
            'attendance_date' => now()->addDay()->toDateString(),
            'records' => $this->recordsFor($staff),
        ])->assertUnprocessable();
    }

    // ── index (history) ─────────────────────────────────────────────────

    public function test_a_school_admin_sees_only_their_schools_history(): void
    {
        [$schoolA, , , $staffA] = $this->makeDepartmentWithHodAndStaff();
        [$schoolB, , , $staffB] = $this->makeDepartmentWithHodAndStaff();
        StaffAttendance::factory()->forStaff($staffA[0])->create();
        StaffAttendance::factory()->forStaff($staffB[0])->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/staff-attendance')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_an_hod_only_sees_history_for_their_own_department(): void
    {
        [$school, , $hod, $staff] = $this->makeDepartmentWithHodAndStaff();
        $otherDepartment = Department::factory()->forSchool($school)->create();
        $outsiderUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $outsider = StaffProfile::factory()->forUser($outsiderUser)->forDepartment($otherDepartment)->create();
        StaffAttendance::factory()->forStaff($staff[0])->create();
        StaffAttendance::factory()->forStaff($outsider)->create();

        $this->actingAs($hod, 'sanctum')->getJson('/api/v1/staff-attendance')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_a_staff_member_cannot_view_the_attendance_history_list(): void
    {
        [$school] = $this->makeDepartmentWithHodAndStaff();
        $staffUser = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staffUser, 'sanctum')->getJson('/api/v1/staff-attendance')->assertForbidden();
    }
}
