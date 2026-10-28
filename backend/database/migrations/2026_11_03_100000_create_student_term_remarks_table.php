<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The class teacher's remark on a student for a term, printed on the progress
 * report above the signature lines (docs/pdf-design.md, phase 3).
 *
 * One per student per term - the unique key - written by the student's class
 * teacher or a School / Group Admin, from the Performance dialog. Clearing
 * the text deletes the row; `written_by` is whoever saved it last.
 *
 * Assessments run on the Python backend only; the table is created here
 * because Laravel's migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('student_term_remarks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_term_id')->constrained('academic_terms')->cascadeOnDelete();
            $table->string('remark', 1000);
            $table->foreignId('written_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['student_id', 'academic_term_id'], 'student_term_remarks_student_term_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('student_term_remarks');
    }
};
