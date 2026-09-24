<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A class test: one subject, one section, one term (docs/assessments.md).
 *
 * The record a teacher sets up before any mark exists. Marks arrive in
 * their own table with the next slice; publishing, which freezes each
 * mark's grade, comes after that. `status` is already meaningful: every
 * assessment starts as a draft, and only a draft may be deleted.
 *
 * `school_id` and `academic_year_id` are snapshotted although both are
 * reachable through the section, matching attendances and
 * timetable_entries: every tenant-scoped query filters on them directly,
 * and CLAUDE.md rule 9 asks for them to be indexed.
 *
 * `syllabus_topic_id` is what the test covered, kept so weak areas can
 * later be reported per topic rather than only per subject. It is
 * nullable because most tests cover more than one topic, and a teacher
 * should not be made to lie about that.
 *
 * `grade_scale_id` is the scale this assessment's grades will be read
 * from, held here rather than looked up at publish so that changing the
 * school's default later cannot silently regrade an old test. Null means
 * marks only, with no grade shown.
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
        Schema::create('assessments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_year_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_term_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->constrained()->cascadeOnDelete();
            $table->foreignId('subject_id')->constrained()->cascadeOnDelete();
            $table->foreignId('syllabus_topic_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('grade_scale_id')->nullable()->constrained()->nullOnDelete();
            $table->string('type', 20); // class_test, assignment, quiz, practical, unit_test.
            $table->string('title', 150); // "Fractions - unit test".
            $table->decimal('max_marks', 6, 2); // Greater than zero, and locked once a mark exists.
            $table->decimal('pass_marks', 6, 2)->nullable();
            $table->decimal('weightage', 5, 2)->nullable(); // Share of the term for that subject, 0-100.
            $table->date('assessment_date'); // A school date, inside the term.
            $table->string('status', 16); // draft, published.
            $table->foreignId('created_by')->constrained('users')->cascadeOnDelete();
            $table->foreignId('published_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('published_at')->nullable();
            $table->timestamps();

            $table->index('school_id');
            $table->index('academic_year_id');
            $table->index('academic_term_id');
            $table->index(['class_section_id', 'subject_id']);
            $table->index('status');
            $table->index('assessment_date');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('assessments');
    }
};
