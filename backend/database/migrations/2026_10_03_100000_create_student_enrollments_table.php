<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which class a student was in, year by year (docs/promotion.md).
 *
 * Until now a student's class lived in exactly one column,
 * `students.class_section_id`. It is single-valued, so the moment a
 * promotion repoints it the fact that the child was ever in Grade 7 A is
 * gone - last year's attendance rows survive only because each snapshots
 * its own section.
 *
 * This table is the history. `students.class_section_id` stays exactly
 * where it is as the pointer to the current year, because every query in
 * the product reads it; one service writes both, in one transaction.
 *
 * `school_class_id` is kept beside the section so a year still reads as
 * "Grade 7" after the section itself is renamed or removed. The section
 * is nullable for the same reason it is on students: a child can exist
 * between class assignments.
 *
 * The unique key on (student_id, academic_year_id) is what stops a double
 * promotion - a rule the database keeps rather than a check that could
 * race two administrators against each other.
 *
 * Promotion itself, and the columns that record which batch moved a
 * student, arrive with `promotion_batches` in a later migration. Nothing
 * here writes an outcome yet: this slice only records who is where.
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
        Schema::create('student_enrollments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_year_id')->constrained()->cascadeOnDelete();
            $table->foreignId('school_class_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->nullable()->constrained()->nullOnDelete();
            $table->string('roll_number', 20)->nullable(); // As it was that year.
            $table->string('status', 16); // studying, promoted, retained, graduated, left.
            $table->timestamps();

            $table->unique(['student_id', 'academic_year_id']);
            $table->index('school_id');
            $table->index('academic_year_id');
            $table->index('class_section_id');
            $table->index('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('student_enrollments');
    }
};
