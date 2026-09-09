<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\Holiday;
use App\Models\School;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class StaffLeaveManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: Department, 2: User, 3: StaffProfile, 4: StaffProfile}
     */
    private function makeDepartmentWithHodAndTeacher(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $hodUser = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hodUser)->create();
        $hodProfile = StaffProfile::factory()->forUser($hodUser)->forDepartment($department)->create();

        $teacherUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $teacherProfile = StaffProfile::factory()->forUser($teacherUser)->forDepartment($department)->create();

        return [$school, $department, $hodUser, $hodProfile, $teacherProfile];
    }

    /**
     * Leave dates are anchored to a Monday so the weekday-only rules (no
     * leave on weekends/holidays, attendance sync on working days only)
     * behave the same no matter which day the suite runs on.
     */
    private function nextMonday(int $plusDays = 0): string
    {
        return now()->next(Carbon::MONDAY)->addDays($plusDays)->toDateString();
    }

    private function leavePayload(array $overrides = []): array
    {
        return array_merge([
            'leave_type' => 'casual',
            'start_date' => $this->nextMonday(),
            'end_date' => $this->nextMonday(1),
            'reason' => 'Family function.',
        ], $overrides);
    }

    // ── apply ────────────────────────────────────────────────────────────

    public function test_a_teacher_can_apply_for_their_own_leave(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $teacher = $teacherProfile->user;

        $response = $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload());

        $response->assertCreated()->assertJsonPath('status', 'pending');
        $this->assertDatabaseHas('staff_leaves', [
            'staff_profile_id' => $teacherProfile->id,
            'school_id' => $school->id,
            'applied_by' => $teacher->id,
            'status' => 'pending',
        ]);
    }

    public function test_an_hod_can_apply_for_their_own_leave(): void
    {
        [, , $hodUser] = $this->makeDepartmentWithHodAndTeacher();

        $this->actingAs($hodUser, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload())
            ->assertCreated();
    }

    /**
     * A School Admin created the normal way (POST /users) gets a minimal
     * auto-created StaffProfile specifically so they can self-service leave
     * like everyone else - see UserService::create().
     */
    /**
     * A (non-sub) School Admin is the head of their school - nobody else
     * has standing to review their leave, so it's auto-approved on
     * application (and immediately synced to attendance, same as any
     * other approval) rather than sitting pending forever.
     * See StaffLeaveService::apply().
     */
    public function test_a_school_admins_own_leave_is_auto_approved_and_synced_to_attendance(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();
        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => $school->id,
        ])->assertCreated();
        $admin = User::where('email', 'priya.sharma@example.com')->firstOrFail();
        $profile = StaffProfile::where('user_id', $admin->id)->firstOrFail();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload());

        $response->assertCreated()
            ->assertJsonPath('status', 'approved')
            ->assertJsonPath('reviewed_by_name', $admin->name);
        $this->assertDatabaseHas('staff_attendances', [
            'staff_profile_id' => $profile->id,
            'attendance_date' => $this->nextMonday(),
            'status' => 'leave',
        ]);
    }

    /**
     * A Sub Admin is still subordinate to the School Admin(s) who created
     * it (see UserPolicy::create()) - their own leave goes through the
     * normal pending -> review flow, not the auto-approval that's specific
     * to the actual head of the school.
     */
    public function test_a_sub_admins_own_leave_still_requires_review(): void
    {
        $school = School::factory()->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);
        StaffProfile::factory()->forUser($subAdmin)->create(['school_id' => $school->id]);

        $response = $this->actingAs($subAdmin, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload());

        $response->assertCreated()->assertJsonPath('status', 'pending');
    }

    /**
     * Edge case: a School Admin who somehow has no StaffProfile (e.g. one
     * created before this auto-creation existed) is still allowed by role,
     * but still gets the same actionable STAFF_PROFILE_REQUIRED error as
     * any other role would - proving the role gate changed, not just a
     * side effect of every School Admin now having a profile.
     */
    public function test_a_school_admin_without_a_staff_profile_gets_a_specific_error(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload());

        $response->assertConflict()->assertJsonPath('code', 'STAFF_PROFILE_REQUIRED');
    }

    public function test_a_super_admin_cannot_apply_for_leave(): void
    {
        $this->makeDepartmentWithHodAndTeacher();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload())
            ->assertForbidden();
    }

    public function test_a_teacher_without_a_linked_staff_profile_gets_a_specific_error(): void
    {
        [$school] = $this->makeDepartmentWithHodAndTeacher();
        $unlinkedTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $response = $this->actingAs($unlinkedTeacher, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload());

        // Distinct from a role-based FORBIDDEN - this actor's role is
        // allowed to apply, they just have no StaffProfile yet, which is a
        // data precondition (409) rather than an authorization failure (403).
        $response->assertConflict()->assertJsonPath('code', 'STAFF_PROFILE_REQUIRED');
        $this->assertDatabaseCount('staff_leaves', 0);
    }

    public function test_a_reason_exceeding_the_max_length_is_rejected(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();

        $this->actingAs($teacherProfile->user, 'sanctum')
            ->postJson('/api/v1/leaves', $this->leavePayload(['reason' => str_repeat('a', 501)]))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['reason']]]);
    }

    public function test_review_remarks_exceeding_the_max_length_are_rejected(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/leaves/{$leave->id}/reject", ['remarks' => str_repeat('a', 501)])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['remarks']]]);
    }

    public function test_end_date_before_start_date_is_rejected(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();

        $this->actingAs($teacherProfile->user, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload([
            'start_date' => $this->nextMonday(3),
            'end_date' => $this->nextMonday(),
        ]))->assertUnprocessable();
    }

    public function test_overlapping_leave_requests_for_the_same_staff_member_are_rejected(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $teacher = $teacherProfile->user;
        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload())->assertCreated();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload([
            'start_date' => $this->nextMonday(1),
            'end_date' => $this->nextMonday(2),
        ]))->assertConflict()->assertJsonPath('code', 'LEAVE_OVERLAP');
    }

    public function test_leave_that_falls_entirely_on_a_weekend_is_rejected(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();

        $this->actingAs($teacherProfile->user, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload([
            'start_date' => $this->nextMonday(5),
            'end_date' => $this->nextMonday(6),
        ]))->assertConflict()->assertJsonPath('code', 'LEAVE_ON_NON_WORKING_DAYS');
    }

    public function test_leave_that_falls_entirely_on_a_holiday_is_rejected(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        Holiday::factory()->forSchool($school)->onDates($this->nextMonday(), $this->nextMonday(1))->create();

        $this->actingAs($teacherProfile->user, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload())
            ->assertConflict()
            ->assertJsonPath('code', 'LEAVE_ON_NON_WORKING_DAYS');
    }

    public function test_leave_spanning_a_holiday_and_a_working_day_is_accepted(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        Holiday::factory()->forSchool($school)->onDates($this->nextMonday())->create();

        $this->actingAs($teacherProfile->user, 'sanctum')->postJson('/api/v1/leaves', $this->leavePayload())
            ->assertCreated();
    }

    // ── review (approve/reject) ─────────────────────────────────────────

    public function test_an_hod_can_approve_leave_for_staff_in_their_department(): void
    {
        [, , $hodUser, , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->create();

        $response = $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve");

        $response->assertOk()->assertJsonPath('status', 'approved');
    }

    public function test_approving_a_leave_marks_every_date_in_range_as_leave_on_the_attendance_register(): void
    {
        [, , $hodUser, , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->onDates($this->nextMonday(), $this->nextMonday(2))->create();

        $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")->assertOk();

        $this->assertDatabaseCount('staff_attendances', 3);
        foreach ([0, 1, 2] as $offset) {
            $this->assertDatabaseHas('staff_attendances', [
                'staff_profile_id' => $teacherProfile->id,
                'attendance_date' => $this->nextMonday($offset),
                'status' => 'leave',
            ]);
        }
    }

    public function test_approving_a_leave_skips_weekends_and_holidays_when_syncing_attendance(): void
    {
        [$school, , $hodUser, , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        // Thursday -> next Monday, with Friday a holiday: only Thursday and Monday are working days.
        Holiday::factory()->forSchool($school)->onDates($this->nextMonday(4))->create();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->onDates($this->nextMonday(3), $this->nextMonday(7))->create();

        $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")->assertOk();

        $this->assertDatabaseCount('staff_attendances', 2);
        $this->assertDatabaseHas('staff_attendances', ['staff_profile_id' => $teacherProfile->id, 'attendance_date' => $this->nextMonday(3)]);
        $this->assertDatabaseHas('staff_attendances', ['staff_profile_id' => $teacherProfile->id, 'attendance_date' => $this->nextMonday(7)]);
        $this->assertDatabaseMissing('staff_attendances', ['attendance_date' => $this->nextMonday(4)]);
        $this->assertDatabaseMissing('staff_attendances', ['attendance_date' => $this->nextMonday(5)]);
    }

    public function test_an_hod_cannot_approve_leave_for_staff_outside_their_department(): void
    {
        [$school, , $hodUser] = $this->makeDepartmentWithHodAndTeacher();
        $otherDepartment = Department::factory()->forSchool($school)->create();
        $outsiderUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $outsiderProfile = StaffProfile::factory()->forUser($outsiderUser)->forDepartment($otherDepartment)->create();
        $leave = StaffLeave::factory()->forStaff($outsiderProfile)->create();

        $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")
            ->assertForbidden();
    }

    public function test_an_hod_cannot_approve_their_own_leave_request(): void
    {
        [, , $hodUser, $hodProfile] = $this->makeDepartmentWithHodAndTeacher();
        $leave = StaffLeave::factory()->forStaff($hodProfile)->create();

        $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")
            ->assertForbidden();
    }

    public function test_a_school_admin_can_reject_leave_in_their_school(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/leaves/{$leave->id}/reject", ['remarks' => 'Insufficient balance.']);

        $response->assertOk()->assertJsonPath('status', 'rejected')->assertJsonPath('review_remarks', 'Insufficient balance.');
        $this->assertDatabaseMissing('staff_attendances', ['staff_profile_id' => $teacherProfile->id]);
    }

    public function test_a_school_admin_cannot_review_leave_from_another_school(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->create();

        $this->actingAs($otherAdmin, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_review_their_own_leave(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->create();

        $this->actingAs($teacherProfile->user, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")
            ->assertForbidden();
    }

    public function test_a_super_admin_can_approve_leave_in_any_school(): void
    {
        [, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->create();

        $this->actingAs($superAdmin, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/approve")
            ->assertOk();
    }

    public function test_reviewing_an_already_reviewed_leave_is_rejected(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $leave = StaffLeave::factory()->forStaff($teacherProfile)->status('approved')->create();

        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/leaves/{$leave->id}/reject")
            ->assertConflict()
            ->assertJsonPath('code', 'LEAVE_ALREADY_REVIEWED');
    }

    // ── index / summary (visibility scoping) ────────────────────────────

    public function test_a_teacher_only_sees_their_own_leave_history(): void
    {
        [$school, $department, , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        $otherTeacherUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $otherTeacherProfile = StaffProfile::factory()->forUser($otherTeacherUser)->forDepartment($department)->create();
        StaffLeave::factory()->forStaff($teacherProfile)->create();
        StaffLeave::factory()->forStaff($otherTeacherProfile)->create();

        $this->actingAs($teacherProfile->user, 'sanctum')->getJson('/api/v1/leaves')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_an_hod_sees_leave_for_their_whole_department(): void
    {
        [, , $hodUser, $hodProfile, $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        StaffLeave::factory()->forStaff($teacherProfile)->create();
        StaffLeave::factory()->forStaff($hodProfile)->create();

        $this->actingAs($hodUser, 'sanctum')->getJson('/api/v1/leaves')
            ->assertOk()
            ->assertJsonCount(2, 'data');
    }

    public function test_a_school_admin_sees_only_their_schools_leave_history(): void
    {
        [$schoolA, , , , $teacherProfileA] = $this->makeDepartmentWithHodAndTeacher();
        [$schoolB, , , , $teacherProfileB] = $this->makeDepartmentWithHodAndTeacher();
        StaffLeave::factory()->forStaff($teacherProfileA)->create();
        StaffLeave::factory()->forStaff($teacherProfileB)->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/leaves')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_the_summary_counts_pending_and_on_leave_today(): void
    {
        [$school, , , , $teacherProfile] = $this->makeDepartmentWithHodAndTeacher();
        StaffLeave::factory()->forStaff($teacherProfile)->create();
        StaffLeave::factory()->forStaff($teacherProfile)->onDates(
            now()->subDay()->toDateString(),
            now()->addDay()->toDateString(),
        )->status('approved')->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/leaves/summary');

        $response->assertOk()
            ->assertJsonPath('pending', 1)
            ->assertJsonPath('on_leave_today', 1);
    }
}
