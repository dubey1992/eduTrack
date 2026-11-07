<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Guardians as people, not as columns on a student (docs/parent-student-app.md,
 * Phase F0).
 *
 * Until now each student carried one guardian's name, mobile and email. A
 * family with two children was two unconnected copies of the same parent, and
 * a child with two parents could only have one. The Family app needs the
 * parent as one person who sees each of their children.
 *
 * guardians - one row per parent or guardian in a school. `login_mobile` is the
 * number they sign in with, digits only with a plus ("+919876543210"), unique
 * within the school; it may be empty for a guardian the school has no number
 * for. `user_id` is set once they are given a way to sign in. `consent_at`
 * records when the school noted the guardian's consent to the Family app
 * (DPDP Act 2023), and who noted it.
 *
 * guardian_student - which guardians belong to which students, and how
 * (mother, father, guardian, other). `is_primary` marks the contact the
 * student's own guardian columns describe; those columns stay, and everything
 * that reads them today keeps working.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('guardians', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->unique()->constrained()->nullOnDelete();
            $table->string('name', 150);
            $table->string('login_mobile', 20)->nullable();
            $table->string('email', 255)->nullable();
            $table->timestamp('consent_at')->nullable();
            $table->foreignId('consent_recorded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['school_id', 'login_mobile']);
        });

        Schema::create('guardian_student', function (Blueprint $table) {
            $table->id();
            $table->foreignId('guardian_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->string('relationship', 20)->default('guardian');
            $table->boolean('is_primary')->default(false);
            $table->timestamps();

            $table->unique(['guardian_id', 'student_id']);
            $table->index('student_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('guardian_student');
        Schema::dropIfExists('guardians');
    }
};
