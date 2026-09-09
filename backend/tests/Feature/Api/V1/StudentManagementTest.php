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

class StudentManagementTest extends TestCase
{
    use RefreshDatabase;

    private function makeSection(School $school): ClassSection
    {
        $year = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($year)->create();

        return ClassSection::factory()->forClass($schoolClass)->create();
    }

    public function test_a_school_admin_can_admit_a_student_into_a_section_in_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $section = $this->makeSection($school);

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/students', [
            'class_section_id' => $section->id,
            'admission_number' => 'STU-0042',
            'first_name' => 'Arjun',
            'last_name' => 'Kumar',
            'roll_number' => '12',
            'guardian_name' => 'Raj Kumar',
            'guardian_mobile' => '+91 9876543210',
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('admission_number', 'STU-0042')
            ->assertJsonPath('status', 'active')
            ->assertJsonPath('class_section_name', "{$section->schoolClass->name} {$section->name}");
    }

    public function test_a_school_admin_can_admit_a_student_even_when_the_client_sends_a_null_school_id(): void
    {
        // The real Flutter client always sends the school_id key (literal
        // null for a non-SuperAdmin) rather than omitting it - a bare
        // `integer` rule without `nullable` rejects that. See
        // StoreStudentRequest.
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $section = $this->makeSection($school);

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/students', [
            'school_id' => null,
            'class_section_id' => $section->id,
            'admission_number' => 'STU-0099',
            'first_name' => 'Sara',
            'last_name' => 'Ali',
            'guardian_name' => 'Imran Ali',
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $school->id);
    }

    public function test_a_school_admin_cannot_admit_a_student_into_a_section_from_another_school(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $sectionElsewhere = $this->makeSection($otherSchool);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/students', [
                'class_section_id' => $sectionElsewhere->id,
                'admission_number' => 'STU-0042',
                'first_name' => 'Arjun',
                'last_name' => 'Kumar',
                'guardian_name' => 'Raj Kumar',
            ])
            ->assertUnprocessable();
    }

    public function test_admission_numbers_are_unique_per_school_but_not_globally(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        Student::factory()->forSection($this->makeSection($schoolA))->create(['admission_number' => 'STU-0001']);
        Student::factory()->forSection($this->makeSection($schoolB))->create(['admission_number' => 'STU-0001']);

        $this->actingAs($adminA, 'sanctum')
            ->postJson('/api/v1/students', [
                'class_section_id' => $this->makeSection($schoolA)->id,
                'admission_number' => 'STU-0001',
                'first_name' => 'New',
                'last_name' => 'Student',
                'guardian_name' => 'Guardian',
            ])
            ->assertUnprocessable();
    }

    public function test_a_school_admin_only_sees_students_from_their_own_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        Student::factory()->forSection($this->makeSection($schoolA))->count(2)->create();
        Student::factory()->forSection($this->makeSection($schoolB))->count(3)->create();

        $response = $this->actingAs($adminA, 'sanctum')->getJson('/api/v1/students');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_cannot_view_a_student_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $studentB = Student::factory()->forSection($this->makeSection($schoolB))->create();

        $this->actingAs($adminA, 'sanctum')
            ->getJson("/api/v1/students/{$studentB->id}")
            ->assertForbidden();
    }

    public function test_a_teacher_can_view_students_only_in_a_section_they_are_the_class_teacher_of(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $ownSection = $this->makeSection($school);
        $ownSection->update(['class_teacher_id' => $teacher->id]);
        $otherSection = $this->makeSection($school);

        $ownStudent = Student::factory()->forSection($ownSection)->create();
        Student::factory()->forSection($otherSection)->create();

        $listResponse = $this->actingAs($teacher, 'sanctum')->getJson('/api/v1/students');
        $listResponse->assertOk();
        $this->assertCount(1, $listResponse->json('data'));
        $this->assertSame($ownStudent->id, $listResponse->json('data.0.id'));

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/students/{$ownStudent->id}")
            ->assertOk();
    }

    public function test_a_teacher_cannot_view_a_student_from_a_section_they_do_not_teach(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $otherSection = $this->makeSection($school);
        $otherStudent = Student::factory()->forSection($otherSection)->create();

        $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/students/{$otherStudent->id}")
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_create_a_student(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = $this->makeSection($school);

        $this->actingAs($teacher, 'sanctum')
            ->postJson('/api/v1/students', [
                'class_section_id' => $section->id,
                'admission_number' => 'STU-0042',
                'first_name' => 'Arjun',
                'last_name' => 'Kumar',
                'guardian_name' => 'Raj Kumar',
            ])
            ->assertForbidden();
    }

    public function test_a_staff_member_cannot_view_the_student_directory(): void
    {
        $school = School::factory()->create();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staff, 'sanctum')
            ->getJson('/api/v1/students')
            ->assertForbidden();
    }

    public function test_a_school_admin_can_deactivate_and_reactivate_a_student(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $student = Student::factory()->forSection($this->makeSection($school))->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/students/{$student->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('status', 'inactive');

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/students/{$student->id}/activate")
            ->assertOk()
            ->assertJsonPath('status', 'active');
    }

    public function test_deleting_a_section_that_still_has_students_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $section = $this->makeSection($school);
        Student::factory()->forSection($section)->create();

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/v1/sections/{$section->id}")
            ->assertStatus(409)
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
    }

    public function test_a_super_admin_is_not_restricted_by_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        Student::factory()->forSection($this->makeSection($schoolA))->create();
        Student::factory()->forSection($this->makeSection($schoolB))->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/students');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }
}
