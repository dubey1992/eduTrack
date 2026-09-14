<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\Driver;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\Subject;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Bulk upload, for the five things a school starts the year with a list of.
 *
 * The rule that shapes all of it: a file either imports completely or not at
 * all. A school that uploads two hundred students and gets a hundred and
 * ninety-nine has a reconciliation problem and no safe way to retry.
 */
class BulkImportTest extends TestCase
{
    use RefreshDatabase;

    private function admin(School $school): User
    {
        return User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
    }

    /**
     * A CSV built the way the template is, so a test reads as the rows it
     * cares about rather than as string plumbing.
     *
     * @param  array<int, string>  $headings
     * @param  array<int, array<int, string>>  $rows
     */
    private function csv(array $headings, array $rows): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'import').'.csv';
        $handle = fopen($path, 'wb');

        fputcsv($handle, $headings);

        foreach ($rows as $row) {
            fputcsv($handle, $row);
        }

        fclose($handle);

        return new UploadedFile($path, 'import.csv', 'text/csv', null, true);
    }

    /** The school's current year, one class, one section - what students need. */
    private function section(School $school, string $class = 'Grade 5', string $name = 'A'): ClassSection
    {
        $year = AcademicYear::factory()->create(['school_id' => $school->id, 'is_current' => true]);
        $schoolClass = SchoolClass::factory()->create([
            'school_id' => $school->id,
            'academic_year_id' => $year->id,
            'name' => $class,
        ]);

        return ClassSection::factory()->create(['school_class_id' => $schoolClass->id, 'name' => $name]);
    }

    private function studentRow(array $overrides = []): array
    {
        return array_values(array_merge([
            'admission_number' => 'ADM-001',
            'first_name' => 'Aarav',
            'last_name' => 'Sharma',
            'class' => 'Grade 5',
            'section' => 'A',
            'roll_number' => '12',
            'guardian_name' => 'Meera Sharma',
            'guardian_mobile' => '+91 98765 43210',
            'address' => '14 Rose Lane',
        ], $overrides));
    }

    private const array STUDENT_HEADINGS = [
        'admission_number', 'first_name', 'last_name', 'class', 'section',
        'roll_number', 'guardian_name', 'guardian_mobile', 'address',
    ];

    // ── the template ────────────────────────────────────────────────────

    public function test_the_template_carries_the_headings_and_one_example_row(): void
    {
        $school = School::factory()->create();

        $response = $this->actingAs($this->admin($school), 'sanctum')->get('/api/v1/imports/students/template');

        $response->assertOk()->assertHeader('Content-Type', 'text/csv; charset=UTF-8');

        $body = $response->streamedContent();

        $this->assertStringContainsString('admission_number,first_name,last_name,class,section', $body);
        // The example row is what stops somebody guessing at the date and
        // phone formats.
        $this->assertStringContainsString('ADM-2026-001', $body);
    }

    public function test_a_template_nobody_offers_is_a_404(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->getJson('/api/v1/imports/parents/template')
            ->assertNotFound();
    }

    // ── students ────────────────────────────────────────────────────────

    public function test_a_school_admin_imports_students(): void
    {
        $school = School::factory()->create();
        $section = $this->section($school);

        $response = $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [
                $this->studentRow(),
                $this->studentRow(['admission_number' => 'ADM-002', 'first_name' => 'Ishaan']),
            ]),
        ]);

        $response->assertCreated()
            ->assertJsonPath('imported', 2)
            ->assertJsonPath('label', 'Students');

        $this->assertSame(2, Student::query()->where('school_id', $school->id)->count());
        $this->assertDatabaseHas('students', [
            'admission_number' => 'ADM-001',
            'school_id' => $school->id,
            'class_section_id' => $section->id,
            'guardian_mobile' => '+91 98765 43210',
            'status' => 'active',
        ]);
    }

    public function test_a_class_and_section_are_matched_however_they_are_capitalised(): void
    {
        $school = School::factory()->create();
        $section = $this->section($school);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow(['class' => 'grade 5', 'section' => 'a'])]),
        ])->assertCreated();

        $this->assertDatabaseHas('students', ['admission_number' => 'ADM-001', 'class_section_id' => $section->id]);
    }

    public function test_a_section_that_does_not_exist_stops_the_whole_file(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $response = $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [
                $this->studentRow(),
                $this->studentRow(['admission_number' => 'ADM-002', 'section' => 'Z']),
            ]),
        ]);

        $response->assertStatus(422)
            ->assertJsonPath('code', 'BULK_IMPORT_FAILED')
            ->assertJsonPath('details.rows.0.row', 3)
            ->assertJsonPath('details.rows.0.messages.0', 'There is no section "Z" in class "Grade 5".');

        // Row two was perfectly good and still did not import.
        $this->assertSame(0, Student::query()->count());
    }

    public function test_every_bad_row_is_reported_at_once(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $response = $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [
                $this->studentRow(['first_name' => '']),
                $this->studentRow(['admission_number' => 'ADM-002', 'guardian_mobile' => '98765']),
                $this->studentRow(['admission_number' => 'ADM-003', 'guardian_name' => '']),
            ]),
        ]);

        $response->assertStatus(422)
            ->assertJsonCount(3, 'details.rows')
            ->assertJsonPath('details.rows.0.row', 2)
            ->assertJsonPath('details.rows.1.row', 3)
            ->assertJsonPath('details.rows.2.row', 4)
            ->assertJsonPath('details.row_count', 3);
    }

    public function test_an_admission_number_repeated_inside_the_file_is_caught(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [
                $this->studentRow(),
                $this->studentRow(['first_name' => 'Ishaan']),
            ]),
        ])
            ->assertStatus(422)
            ->assertJsonPath('details.rows.0.row', 3)
            ->assertJsonPath('details.rows.0.messages.0', 'The admission_number "ADM-001" is also on row 2.');
    }

    public function test_an_admission_number_already_in_the_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $section = $this->section($school);
        Student::factory()->create([
            'school_id' => $school->id,
            'class_section_id' => $section->id,
            'admission_number' => 'ADM-001',
        ]);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
        ])->assertStatus(422);

        $this->assertSame(1, Student::query()->count());
    }

    public function test_the_same_admission_number_is_free_at_another_school(): void
    {
        $school = School::factory()->create();
        $other = School::factory()->create();
        $otherSection = $this->section($other);
        Student::factory()->create([
            'school_id' => $other->id,
            'class_section_id' => $otherSection->id,
            'admission_number' => 'ADM-001',
        ]);

        $this->section($school);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
        ])->assertCreated();
    }

    public function test_a_school_without_a_current_year_is_told_so_plainly(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
        ])
            ->assertStatus(422)
            ->assertJsonPath(
                'details.rows.0.messages.0',
                'This school has no classes in its current academic year yet. Set one up before importing students.',
            );
    }

    // ── the file itself ─────────────────────────────────────────────────

    public function test_headings_that_do_not_match_the_template_are_refused(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(['admission_number', 'name'], [['ADM-001', 'Aarav']]),
        ])
            ->assertStatus(422)
            ->assertJsonPath('details.rows.0.row', 1)
            ->assertJsonFragment(['row_count' => 0]);
    }

    public function test_a_file_with_headings_and_nothing_else_says_so(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, []),
        ])
            ->assertStatus(422)
            ->assertJsonPath('details.rows.0.messages.0', 'The file has headings but no rows.');
    }

    public function test_the_blank_line_a_spreadsheet_leaves_behind_is_ignored(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $path = tempnam(sys_get_temp_dir(), 'import').'.csv';
        file_put_contents(
            $path,
            implode(',', self::STUDENT_HEADINGS)."\n".implode(',', $this->studentRow())."\n,,,,,,,,\n\n",
        );

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => new UploadedFile($path, 'import.csv', 'text/csv', null, true),
        ])
            ->assertCreated()
            ->assertJsonPath('imported', 1);
    }

    public function test_a_byte_order_mark_does_not_break_the_first_heading(): void
    {
        $school = School::factory()->create();
        $this->section($school);

        $path = tempnam(sys_get_temp_dir(), 'import').'.csv';
        file_put_contents(
            $path,
            "\xEF\xBB\xBF".implode(',', self::STUDENT_HEADINGS)."\n".implode(',', $this->studentRow())."\n",
        );

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => new UploadedFile($path, 'import.csv', 'text/csv', null, true),
        ])->assertCreated();
    }

    public function test_something_that_is_not_a_csv_is_refused(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/imports/students', ['file' => UploadedFile::fake()->image('roll.png')])
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_ERROR');
    }

    // ── staff ───────────────────────────────────────────────────────────

    private const array STAFF_HEADINGS = [
        'employee_id', 'first_name', 'last_name', 'email', 'mobile',
        'role', 'department', 'designation', 'joining_date', 'address',
    ];

    private function staffRow(array $overrides = []): array
    {
        return array_values(array_merge([
            'employee_id' => 'EMP-1',
            'first_name' => 'Priya',
            'last_name' => 'Nair',
            'email' => 'priya.nair@example.com',
            'mobile' => '+91 98765 43210',
            'role' => 'TEACHER',
            'department' => 'Science',
            'designation' => 'Senior Teacher',
            'joining_date' => '09/14/2026',
            'address' => '22 Hill Road',
        ], $overrides));
    }

    public function test_importing_staff_generates_a_password_and_asks_for_it_to_be_changed(): void
    {
        $school = School::factory()->create();
        $department = Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);

        $response = $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow()]),
        ]);

        $response->assertCreated()->assertJsonPath('imported', 1);

        $password = $response->json('details.0.temporary_password');
        $this->assertNotEmpty($password);

        $user = User::query()->where('email', 'priya.nair@example.com')->firstOrFail();

        $this->assertTrue($user->must_change_password);
        $this->assertTrue(Hash::check($password, $user->password));
        $this->assertSame(UserRole::Teacher, $user->role);
        $this->assertSame($school->id, $user->school_id);

        $this->assertDatabaseHas('staff_profiles', [
            'user_id' => $user->id,
            'employee_id' => 'EMP-1',
            'department_id' => $department->id,
            'joining_date' => '2026-09-14',
        ]);
    }

    public function test_a_joining_date_written_without_leading_zeros_still_reads(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow(['joining_date' => '9/4/2026'])]),
        ])->assertCreated();

        $this->assertDatabaseHas('staff_profiles', ['employee_id' => 'EMP-1', 'joining_date' => '2026-09-04']);
    }

    public function test_a_date_in_the_other_order_is_refused_rather_than_guessed_at(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);

        // 14/09/2026 is not a US date, and reading it as one would silently
        // file the employee under a month that does not exist.
        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow(['joining_date' => '14/09/2026'])]),
        ])->assertStatus(422);

        $this->assertSame(0, StaffProfile::query()->count());
    }

    public function test_a_role_is_read_however_it_is_capitalised(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow(['role' => 'Teacher'])]),
        ])->assertCreated();

        $this->assertSame(
            UserRole::Teacher,
            User::query()->where('email', 'priya.nair@example.com')->firstOrFail()->role,
        );
    }

    public function test_an_import_cannot_create_an_admin_account(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow(['role' => 'SCHOOL_ADMIN'])]),
        ])->assertStatus(422);

        $this->assertNull(User::query()->where('email', 'priya.nair@example.com')->first());
    }

    public function test_a_department_belonging_to_another_school_is_not_a_department(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => School::factory()->create()->id, 'name' => 'Science']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow()]),
        ])->assertStatus(422);
    }

    public function test_an_email_already_in_use_anywhere_is_rejected(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);
        User::factory()->create(['email' => 'priya.nair@example.com']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/staff', [
            'file' => $this->csv(self::STAFF_HEADINGS, [$this->staffRow()]),
        ])->assertStatus(422);
    }

    // ── subjects, vehicles and drivers ──────────────────────────────────

    public function test_a_school_admin_imports_subjects(): void
    {
        $school = School::factory()->create();
        $department = Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create(['email' => 'lead@example.com']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/subjects', [
            'file' => $this->csv(
                ['code', 'name', 'department', 'min_class_level', 'max_class_level', 'lead_teacher_email'],
                [['SCI-05', 'Science', 'Science', '5', '8', 'lead@example.com']],
            ),
        ])->assertCreated();

        $this->assertDatabaseHas('subjects', [
            'school_id' => $school->id,
            'code' => 'SCI-05',
            'department_id' => $department->id,
            'lead_teacher_id' => $teacher->id,
            'min_class_level' => 5,
            'max_class_level' => 8,
        ]);
    }

    public function test_a_subject_whose_class_range_runs_backwards_is_refused(): void
    {
        $school = School::factory()->create();
        Department::factory()->create(['school_id' => $school->id, 'name' => 'Science']);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/subjects', [
            'file' => $this->csv(
                ['code', 'name', 'department', 'min_class_level', 'max_class_level', 'lead_teacher_email'],
                [['SCI-05', 'Science', 'Science', '8', '5', '']],
            ),
        ])
            ->assertStatus(422)
            ->assertJsonPath(
                'details.rows.0.messages.0',
                'The max class level must be at or above the min class level.',
            );

        $this->assertSame(0, Subject::query()->count());
    }

    public function test_a_school_admin_imports_vehicles(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/vehicles', [
            'file' => $this->csv(
                ['name', 'registration_number', 'capacity'],
                [['Bus 12', 'MH 12 AB 3456', '42'], ['Bus 13', 'MH 12 AB 3457', '42']],
            ),
        ])->assertCreated()->assertJsonPath('imported', 2);

        $this->assertDatabaseHas('vehicles', [
            'school_id' => $school->id,
            'registration_number' => 'MH 12 AB 3456',
            'capacity' => 42,
            'status' => 'active',
        ]);
    }

    public function test_a_vehicle_with_an_impossible_capacity_stops_the_file(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/vehicles', [
            'file' => $this->csv(
                ['name', 'registration_number', 'capacity'],
                [['Bus 12', 'MH 12 AB 3456', '0']],
            ),
        ])->assertStatus(422);

        $this->assertSame(0, Vehicle::query()->count());
    }

    public function test_a_school_admin_imports_drivers(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/drivers', [
            'file' => $this->csv(
                ['name', 'mobile', 'licence_number', 'licence_expiry'],
                [['Ramesh Yadav', '+91 98765 43210', 'MH1220260001234', '09/14/2029']],
            ),
        ])->assertCreated();

        $this->assertDatabaseHas('drivers', [
            'school_id' => $school->id,
            'licence_number' => 'MH1220260001234',
            'licence_expiry' => '2029-09-14',
            'status' => 'active',
        ]);
    }

    public function test_a_driver_without_an_expiry_date_is_fine(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/drivers', [
            'file' => $this->csv(
                ['name', 'mobile', 'licence_number', 'licence_expiry'],
                [['Ramesh Yadav', '', 'MH1220260001234', '']],
            ),
        ])->assertCreated();

        $this->assertDatabaseHas('drivers', ['licence_number' => 'MH1220260001234', 'licence_expiry' => null]);
        $this->assertSame(null, Driver::query()->firstOrFail()->mobile);
    }

    // ── who may import ──────────────────────────────────────────────────

    public function test_a_super_admin_imports_into_the_school_they_name(): void
    {
        $school = School::factory()->create();
        $this->section($school);
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
            'school_id' => $school->id,
        ])->assertCreated();

        $this->assertDatabaseHas('students', ['admission_number' => 'ADM-001', 'school_id' => $school->id]);
    }

    public function test_a_super_admin_must_say_which_school(): void
    {
        $school = School::factory()->create();
        $this->section($school);
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
        ], ['Accept' => 'application/json'])
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_ERROR')
            ->assertJsonPath('details.errors.school_id.0', 'The school id field is required.');

        $this->assertSame(0, Student::query()->count());
    }

    public function test_a_school_admin_cannot_import_into_another_school(): void
    {
        $school = School::factory()->create();
        $other = School::factory()->create();
        $this->section($school);
        $this->section($other);

        $this->actingAs($this->admin($school), 'sanctum')->post('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
            // Ignored: the school comes from the account, never the request.
            'school_id' => $other->id,
        ])->assertCreated();

        $this->assertDatabaseHas('students', ['admission_number' => 'ADM-001', 'school_id' => $school->id]);
        $this->assertSame(0, Student::query()->where('school_id', $other->id)->count());
    }

    public function test_a_teacher_cannot_import_students(): void
    {
        $school = School::factory()->create();
        $this->section($school);
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/imports/students', [
            'file' => $this->csv(self::STUDENT_HEADINGS, [$this->studentRow()]),
        ])->assertForbidden();

        $this->assertSame(0, Student::query()->count());
    }

    public function test_a_teacher_cannot_even_see_the_staff_template(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->getJson('/api/v1/imports/staff/template')->assertForbidden();
    }

    public function test_importing_needs_a_signed_in_account(): void
    {
        $this->postJson('/api/v1/imports/students')->assertUnauthorized();
        $this->getJson('/api/v1/imports/students/template')->assertUnauthorized();
    }
}
