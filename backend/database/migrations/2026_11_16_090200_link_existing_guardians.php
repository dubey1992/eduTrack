<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Turns each student's guardian columns into a guardian and a link
 * (docs/parent-student-app.md, F0).
 *
 * Within a school, one mobile number is one person: siblings who list the same
 * number get the same guardian. A student with no number gets a guardian of
 * their own, by name only. Every link made here is the student's primary
 * contact, as the columns were.
 *
 * Nothing is removed from `students`: the alerts, imports and screens that
 * read the guardian columns today keep reading them.
 *
 * Runs once. A guardian or link already there is left alone, so it is safe
 * on a database where some were added by hand. `down` removes nothing that
 * somebody may since have edited.
 */
return new class extends Migration
{
    public function up(): void
    {
        $now = now();

        DB::table('students')
            ->whereNotNull('guardian_name')
            ->where('guardian_name', '<>', '')
            ->orderBy('id')
            ->select(['id', 'school_id', 'guardian_name', 'guardian_mobile', 'guardian_email'])
            ->chunk(500, function ($students) use ($now) {
                foreach ($students as $student) {
                    $mobile = $this->loginMobile($student->guardian_mobile);
                    $guardianId = $mobile === null ? null : DB::table('guardians')
                        ->where('school_id', $student->school_id)
                        ->where('login_mobile', $mobile)
                        ->value('id');

                    if ($guardianId === null) {
                        $guardianId = DB::table('guardians')->insertGetId([
                            'school_id' => $student->school_id,
                            'name' => mb_substr(trim($student->guardian_name), 0, 150),
                            'login_mobile' => $mobile,
                            'email' => $student->guardian_email ?: null,
                            'created_at' => $now,
                            'updated_at' => $now,
                        ]);
                    }

                    $linked = DB::table('guardian_student')
                        ->where('guardian_id', $guardianId)
                        ->where('student_id', $student->id)
                        ->exists();

                    if (! $linked) {
                        DB::table('guardian_student')->insert([
                            'guardian_id' => $guardianId,
                            'student_id' => $student->id,
                            'relationship' => 'guardian',
                            'is_primary' => true,
                            'created_at' => $now,
                            'updated_at' => $now,
                        ]);
                    }
                }
            });
    }

    public function down(): void
    {
        // Nothing: see the note above.
    }

    /** "+91 98765 43210" as the sign-in key: a plus and the digits. */
    private function loginMobile(?string $mobile): ?string
    {
        $digits = preg_replace('/\D/', '', (string) $mobile);

        return $digits === '' ? null : '+'.$digits;
    }
};
