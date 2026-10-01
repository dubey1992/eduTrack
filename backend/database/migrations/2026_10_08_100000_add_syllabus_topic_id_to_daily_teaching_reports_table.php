<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which syllabus topic a day's lesson was about (docs/insights.md, slice 3).
 *
 * `topic_taught` has always been free text, and the syllabus has always been
 * ticked off on its own screen, so a teacher who taught Newton's laws wrote
 * it once in the daily report and ticked it a second time under Syllabus.
 * This column is what lets filing the report do both.
 *
 * **Nullable, and `topic_taught` stays.** Two reasons it would be wrong to
 * replace the text with the foreign key: a lesson is often not a syllabus
 * topic at all - a revision period, a test, a visiting speaker - and every
 * report filed before today has only the text. The column names the topic
 * when there is one to name, and the text keeps saying what happened.
 *
 * `nullOnDelete` rather than cascade: deleting a topic from a syllabus must
 * not delete the record that a lesson was taught.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('daily_teaching_reports', function (Blueprint $table) {
            $table->foreignId('syllabus_topic_id')
                ->nullable()
                ->after('topic_taught')
                ->constrained('syllabus_topics')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('daily_teaching_reports', function (Blueprint $table) {
            $table->dropForeign(['syllabus_topic_id']);
            $table->dropColumn('syllabus_topic_id');
        });
    }
};
