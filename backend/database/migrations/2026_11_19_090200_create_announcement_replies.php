<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Notices that ask parents for an answer - a consent slip, an RSVP
 * (docs/parent-student-app.md, F5, decided 2026-11-17).
 *
 * The school writes a question on the announcement ("Can your child come on
 * the trip to the science museum?"); parents answer Yes or No in the Family
 * app, with a note if they want. One answer per child, not per parent: a
 * parent of two children in the class answers for each, and the school's
 * count is of children, which is what a trip needs.
 *
 * - announcements.reply_question: null for a notice that asks nothing
 * - announcements.reply_by: the last day answers are taken, if any
 * - announcement_replies: one row per announcement and child, the latest
 *   answer winning (a parent may change their mind until reply_by)
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('announcements', function (Blueprint $table) {
            $table->string('reply_question', 200)->nullable();
            $table->date('reply_by')->nullable();
        });

        Schema::create('announcement_replies', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('announcement_id')->constrained();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('answered_by')->constrained('users');
            $table->boolean('answer');
            $table->string('note', 300)->nullable();
            $table->timestamps();

            $table->unique(['announcement_id', 'student_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('announcement_replies');

        Schema::table('announcements', function (Blueprint $table) {
            $table->dropColumn(['reply_question', 'reply_by']);
        });
    }
};
