<?php

/**
 * Seeds (or tears down) the fixture users the Phase 9 Flutter integration
 * test (frontend/integration_test/staff_leave_flow_test.dart) needs in
 * whatever database this script's Laravel app is configured against - a
 * Teacher and the HOD of their department, both password "password".
 * Idempotent: always cleans up any previous run of its own fixtures first,
 * so it's safe to re-run without a separate "clean" step in between.
 *
 * Usage (from backend/):
 *   php tests/Support/seed_staff_leave_fixtures.php seed
 *   php tests/Support/seed_staff_leave_fixtures.php clean
 */

require __DIR__.'/../../vendor/autoload.php';

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\School;
use App\Models\StaffAttendance;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;

const TEACHER_EMAIL = 'itest-teacher@example.com';
const HOD_EMAIL = 'itest-hod@example.com';
const SCHOOL_NAME = 'Integration Test School';

function cleanFixtures(): void
{
    $school = School::where('name', SCHOOL_NAME)->first();
    if ($school === null) {
        return;
    }

    StaffLeave::where('school_id', $school->id)->delete();
    StaffAttendance::where('school_id', $school->id)->delete();
    StaffProfile::where('school_id', $school->id)->delete();
    Department::where('school_id', $school->id)->delete();
    User::where('school_id', $school->id)->delete();
    $school->delete();
}

$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$command = $argv[1] ?? 'seed';

if ($command === 'clean') {
    cleanFixtures();
    echo "Cleaned up integration test fixtures.\n";
    exit(0);
}

cleanFixtures();

$school = School::factory()->create(['name' => SCHOOL_NAME]);
$hodUser = User::factory()->role(UserRole::Hod)->forSchool($school)->create([
    'email' => HOD_EMAIL,
    'password' => bcrypt('password'),
]);
$department = Department::factory()->forSchool($school)->withHod($hodUser)->create();
StaffProfile::factory()->forUser($hodUser)->forDepartment($department)->create();

$teacherUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create([
    'email' => TEACHER_EMAIL,
    'password' => bcrypt('password'),
]);
StaffProfile::factory()->forUser($teacherUser)->forDepartment($department)->create();

echo 'Seeded integration test fixtures: school #'.$school->id.', HOD '.HOD_EMAIL.', Teacher '.TEACHER_EMAIL.PHP_EOL;
