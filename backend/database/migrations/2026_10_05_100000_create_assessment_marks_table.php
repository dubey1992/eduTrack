<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One student's mark in one class test (docs/assessments.md).
 *
 * The sheet is saved as a whole, so these rows are written as a set: one
 * request per class, not one per child. The unique key is what makes that
 * safe to repeat - saving the same sheet twice updates the same rows.
 *
 * `marks_obtained` is null when the student was absent, and absent is not
 * zero: an absentee leaves the average's denominator rather than dragging
 * it down. Both facts are needed, which is why `is_absent` is its own
 * column and not a magic value in the mark.
 *
 * `grade` is written at publish, from the assessment's grade scale, and
 * frozen there. Editing a band afterwards cannot rewrite a result a
 * guardian has already been told about - the same reasoning as a finalized
 * payslip. Publishing arrives with the next slice; the column is created
 * here because it belongs to this row.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('assessment_marks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('assessment_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->decimal('marks_obtained', 6, 2)->nullable(); // Null when absent.
            $table->boolean('is_absent')->default(false);
            $table->string('grade', 10)->nullable(); // Frozen at publish.
            $table->string('remarks', 255)->nullable();
            $table->foreignId('entered_by')->constrained('users')->cascadeOnDelete();
            $table->timestamps();

            $table->unique(['assessment_id', 'student_id'], 'assessment_marks_assessment_student_unique');
            $table->index('school_id');
            $table->index('student_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('assessment_marks');
    }
};
