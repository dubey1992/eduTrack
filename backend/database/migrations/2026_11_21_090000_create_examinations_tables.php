<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Examinations and admit cards (docs/examinations.md, decided 2026-11-17).
 *
 * Until now the product had class tests (one section, one subject, one date)
 * and no examination: nothing named "Half-Yearly 2026" with a date sheet, a
 * centre and a reporting time, and nothing to print an admit card from.
 *
 * - examinations: one exam of one school's academic year - its name, an
 *   optional term, the centre, the reporting time, the instructions printed
 *   on the card, the card's look, whether overdue fees hold a card back, and
 *   whether it is a draft or published (with the version last published).
 * - examination_papers: the date sheet - one subject for one class on one
 *   day, from a start time to an end time, in the school's own wall-clock
 *   time (dates and times, never instants).
 * - examination_versions: what each publish issued, frozen as JSON, so a
 *   card printed from version 1 reprints exactly as it was after version 2
 *   moved a paper. A card is only ever printed from one of these.
 * - examination_exceptions: one student's card held back by the school
 *   ("withhold", with the reason staff read), or let through a fee-due hold
 *   ("allow").
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('examinations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('academic_year_id')->constrained();
            $table->foreignId('academic_term_id')->nullable()->constrained();
            $table->string('name', 100);
            $table->string('centre', 150)->nullable();
            $table->time('reporting_time')->nullable();
            $table->text('instructions')->nullable();
            $table->string('card_style', 20)->default('classic');
            $table->boolean('block_on_fee_dues')->default(false);
            $table->string('status', 20)->default('draft');
            $table->unsignedInteger('version')->default(0);
            $table->timestamp('published_at')->nullable();
            $table->foreignId('published_by')->nullable()->constrained('users');
            $table->foreignId('created_by')->nullable()->constrained('users');
            $table->timestamps();

            $table->unique(['school_id', 'academic_year_id', 'name']);
            $table->index(['school_id', 'status']);
        });

        Schema::create('examination_papers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('examination_id')->constrained();
            $table->foreignId('school_class_id')->constrained('school_classes');
            $table->foreignId('subject_id')->constrained();
            $table->date('exam_date');
            $table->time('start_time');
            $table->time('end_time');
            $table->timestamps();

            $table->unique(['examination_id', 'school_class_id', 'subject_id']);
            $table->index(['examination_id', 'school_class_id', 'exam_date']);
        });

        Schema::create('examination_versions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('examination_id')->constrained();
            $table->unsignedInteger('version');
            $table->json('snapshot');
            $table->timestamp('published_at');
            $table->foreignId('published_by')->nullable()->constrained('users');
            $table->timestamps();

            $table->unique(['examination_id', 'version']);
        });

        Schema::create('examination_exceptions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('examination_id')->constrained();
            $table->foreignId('student_id')->constrained();
            $table->string('kind', 20);
            $table->string('reason', 255)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users');
            $table->timestamps();

            $table->unique(['examination_id', 'student_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('examination_exceptions');
        Schema::dropIfExists('examination_versions');
        Schema::dropIfExists('examination_papers');
        Schema::dropIfExists('examinations');
    }
};
