<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A topic belongs to a class, shared by all of its sections (decided
     * 2026-11-05): Computer Science for Playgroup is not Computer Science for
     * Class 9. Stored as the class level - Playgroup -3 to Class 12 - rather
     * than a class row, because classes are made afresh each academic year
     * and a syllabus carries over from one year to the next.
     *
     * Null is a topic written before this existed, which still applies to
     * every class until somebody gives it one.
     */
    public function up(): void
    {
        Schema::table('syllabus_topics', function (Blueprint $table) {
            $table->smallInteger('class_level')->nullable()->after('subject_id');
        });

        // The order is now per subject per class. The new index comes first:
        // on MySQL the subject foreign key leans on whichever index leads with
        // subject_id, and the old one cannot go until another does.
        Schema::table('syllabus_topics', function (Blueprint $table) {
            $table->unique(['subject_id', 'class_level', 'sequence_number'], 'syllabus_topics_subject_level_sequence_unique');
        });

        Schema::table('syllabus_topics', function (Blueprint $table) {
            $table->dropUnique(['subject_id', 'sequence_number']);
        });
    }

    public function down(): void
    {
        Schema::table('syllabus_topics', function (Blueprint $table) {
            $table->unique(['subject_id', 'sequence_number']);
        });

        Schema::table('syllabus_topics', function (Blueprint $table) {
            $table->dropUnique('syllabus_topics_subject_level_sequence_unique');
            $table->dropColumn('class_level');
        });
    }
};
