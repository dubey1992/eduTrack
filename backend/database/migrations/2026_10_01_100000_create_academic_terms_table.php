<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Terms: the named, dated slices of an academic year (docs/assessments.md).
 *
 * A year carried only `is_current` until now, so there was no period a result
 * could belong to and no natural span for "how is this child doing". A term
 * gives both. It is the first table of the assessments work, and the only one
 * that means anything on its own - a school can set out its terms today and
 * nothing else changes.
 *
 * The two unique keys are per year rather than per school, for the same
 * reason "Grade 8" repeats every year: next year has its own Term 1, and it
 * is a different term.
 *
 * `school_id` is snapshotted beside `academic_year_id` although it is
 * reachable through the year, matching academic_years, attendances and
 * timetable_entries - every tenant-scoped query filters on it directly and
 * CLAUDE.md rule 9 asks for it to be indexed.
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
        Schema::create('academic_terms', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_year_id')->constrained()->cascadeOnDelete();
            $table->string('name', 50); // "Term 1", "Final".
            $table->unsignedTinyInteger('sequence_number'); // Curriculum order within the year.
            $table->date('start_date');
            $table->date('end_date'); // Inside the year, and never overlapping a sibling term.
            $table->timestamps();

            $table->unique(['academic_year_id', 'name']);
            $table->unique(['academic_year_id', 'sequence_number'], 'academic_terms_year_sequence_unique');
            $table->index('school_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('academic_terms');
    }
};
