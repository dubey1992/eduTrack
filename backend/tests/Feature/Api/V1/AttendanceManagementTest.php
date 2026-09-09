<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Attendance;
use App\Models\ClassSection;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AttendanceManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: ClassSection, 2: User, 3: array<int, Student>}
     */
    private function makeClassWithTeacherAndStudents(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = ClassSection::factory()->forClass($schoolClass)->withClassTeacher($teacher)->create();
        $students = Student::factory()->forSection($section)->count(3)->create();

        return [$school, $section, $teacher, $students];
    }

    private function recordsFor(iterable $students, string $status = 'present'): array
    {
        return collect($students)->map(fn (Student $s) => ['student_id' => $s->id, 'status' => $status])->all();
    }

    // ── register ─────────────────────────────────────────────────────────

    public function test_a_class_teacher_can_view_their_own_class_register(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();

        $response = $this->actingAs($teacher, 'sanctum')->getJson(
            "/api/v1/attendance/register?class_section_id={$section->id}&date=".now()->toDateString()
        );

        $response->assertOk()
            ->assertJsonPath('submitted', false)
            ->assertJsonCount(3, 'students');
    }

    public function test_a_teacher_cannot_view_another_teachers_class_register(): void
    {
        [$school, $section] = $this->makeClassWithTeacherAndStudents();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($otherTeacher, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date=".now()->toDateString())
            ->assertForbidden();
    }

    public function test_a_school_admin_can_view_any_class_register_in_their_school(): void
    {
        [$school, $section] = $this->makeClassWithTeacherAndStudents();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date=".now()->toDateString())
            ->assertOk();
    }

    public function test_a_school_admin_cannot_view_a_register_from_another_school(): void
    {
        [, $section] = $this->makeClassWithTeacherAndStudents();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date=".now()->toDateString())
            ->assertForbidden();
    }

    public function test_staff_cannot_view_any_class_register(): void
    {
        [$school, $section] = $this->makeClassWithTeacherAndStudents();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staff, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date=".now()->toDateString())
            ->assertForbidden();
    }

    public function test_registering_for_a_future_date_is_rejected(): void
    {
        [, $section, $teacher] = $this->makeClassWithTeacherAndStudents();

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/attendance/register?class_section_id={$section->id}&date=".now()->addDay()->toDateString())
            ->assertUnprocessable();
    }

    // ── store (submit) ───────────────────────────────────────────────────

    public function test_a_class_teacher_can_submit_attendance_for_their_own_class(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();

        $response = $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => [
                ['student_id' => $students[0]->id, 'status' => 'present'],
                ['student_id' => $students[1]->id, 'status' => 'absent', 'remarks' => 'Sick'],
                ['student_id' => $students[2]->id, 'status' => 'leave'],
            ],
        ]);

        $response->assertCreated()->assertJsonPath('submitted', true);
        $this->assertDatabaseHas('attendances', [
            'class_section_id' => $section->id,
            'student_id' => $students[1]->id,
            'status' => 'absent',
            'remarks' => 'Sick',
            'marked_by' => $teacher->id,
        ]);
        // Never trusted from the client - always derived from the section.
        $this->assertDatabaseHas('attendances', [
            'class_section_id' => $section->id,
            'school_id' => $section->schoolClass->school_id,
            'academic_year_id' => $section->schoolClass->academic_year_id,
        ]);
    }

    public function test_a_teacher_cannot_submit_attendance_for_another_teachers_class(): void
    {
        [$school, $section, , $students] = $this->makeClassWithTeacherAndStudents();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($otherTeacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => $this->recordsFor($students),
        ])->assertForbidden();
    }

    public function test_submitting_attendance_twice_for_the_same_class_and_day_is_rejected(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();
        $payload = [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => $this->recordsFor($students),
        ];
        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', $payload)->assertCreated();

        $response = $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', $payload);

        $response->assertStatus(409)->assertJsonPath('code', 'ATTENDANCE_ALREADY_SUBMITTED');
    }

    public function test_submitting_a_duplicate_student_within_the_same_request_is_rejected(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => [
                ['student_id' => $students[0]->id, 'status' => 'present'],
                ['student_id' => $students[0]->id, 'status' => 'absent'],
            ],
        ])->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['records']]]);
    }

    public function test_submitting_a_student_from_a_different_class_is_rejected(): void
    {
        [, $section, $teacher] = $this->makeClassWithTeacherAndStudents();
        $otherStudent = Student::factory()->create();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => [['student_id' => $otherStudent->id, 'status' => 'present']],
        ])->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['records.0.student_id']]]);
    }

    public function test_submitting_for_an_inactive_student_is_rejected(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();
        $students[0]->update(['status' => 'inactive']);

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => [['student_id' => $students[0]->id, 'status' => 'present']],
        ])->assertUnprocessable();
    }

    public function test_submitting_for_a_future_date_is_rejected(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->addDay()->toDateString(),
            'records' => $this->recordsFor($students),
        ])->assertUnprocessable();
    }

    public function test_submitting_an_invalid_status_is_rejected(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => [['student_id' => $students[0]->id, 'status' => 'half_day']],
        ])->assertUnprocessable();
    }

    // ── update (edit an already-submitted day) ──────────────────────────

    public function test_a_class_teacher_can_edit_an_already_submitted_day(): void
    {
        [, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();
        $date = now()->toDateString();
        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => $date,
            'records' => $this->recordsFor($students, 'present'),
        ])->assertCreated();

        $response = $this->actingAs($teacher, 'sanctum')->patchJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => $date,
            'records' => [['student_id' => $students[0]->id, 'status' => 'absent', 'remarks' => 'Called in sick']],
        ]);

        $response->assertOk();
        $this->assertDatabaseHas('attendances', [
            'class_section_id' => $section->id,
            'student_id' => $students[0]->id,
            'status' => 'absent',
            'remarks' => 'Called in sick',
        ]);
        // Only one row per student per day - update() upserts, it never
        // duplicates the original row.
        $this->assertDatabaseCount('attendances', 3);
    }

    public function test_a_teacher_cannot_edit_another_teachers_class_attendance(): void
    {
        [$school, $section, , $students] = $this->makeClassWithTeacherAndStudents();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($otherTeacher, 'sanctum')->patchJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => now()->toDateString(),
            'records' => $this->recordsFor($students),
        ])->assertForbidden();
    }

    // ── index (history list) ────────────────────────────────────────────

    public function test_a_super_admin_sees_attendance_from_every_school(): void
    {
        [, $sectionA, , $studentsA] = $this->makeClassWithTeacherAndStudents();
        [, $sectionB, , $studentsB] = $this->makeClassWithTeacherAndStudents();
        Attendance::factory()->forStudent($studentsA[0])->create();
        Attendance::factory()->forStudent($studentsB[0])->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/attendance');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_only_sees_attendance_from_their_own_school(): void
    {
        [$schoolA, , , $studentsA] = $this->makeClassWithTeacherAndStudents();
        [, , , $studentsB] = $this->makeClassWithTeacherAndStudents();
        Attendance::factory()->forStudent($studentsA[0])->create();
        Attendance::factory()->forStudent($studentsB[0])->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();

        $response = $this->actingAs($adminA, 'sanctum')->getJson('/api/v1/attendance');

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
        $this->assertSame($studentsA[0]->id, $response->json('data.0.student_id'));
    }

    public function test_a_teacher_only_sees_attendance_from_classes_they_teach(): void
    {
        [$school, $section, $teacher, $students] = $this->makeClassWithTeacherAndStudents();
        [, , , $otherStudents] = $this->makeClassWithTeacherAndStudents($school);
        Attendance::factory()->forStudent($students[0])->create();
        Attendance::factory()->forStudent($otherStudents[0])->create();

        $response = $this->actingAs($teacher, 'sanctum')->getJson('/api/v1/attendance');

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
        $this->assertSame($section->id, $response->json('data.0.class_section_id'));
    }

    public function test_an_unauthenticated_request_cannot_list_attendance(): void
    {
        $this->getJson('/api/v1/attendance')->assertUnauthorized();
    }

    public function test_a_transport_manager_cannot_list_attendance(): void
    {
        $school = School::factory()->create();
        $transportManager = User::factory()->role(UserRole::TransportManager)->forSchool($school)->create();

        $this->actingAs($transportManager, 'sanctum')->getJson('/api/v1/attendance')->assertForbidden();
    }
}
