<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "Please call me" from a parent in the Family app
 * (docs/parent-student-app.md, F5, decided 2026-11-17).
 *
 * The parent picks who should call - the child's class teacher or the school
 * office - says what it is about and, if they like, when suits them. Whoever
 * it is for calls the parent's number and marks it called, with a note of how
 * it went; the parent sees it marked called. No open chat (decision D5).
 *
 * - recipient: class_teacher | office
 * - teacher_user_id: the class teacher when it was sent, so a later change of
 *   class teacher does not move a request already made
 * - status: open | called
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('call_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('requested_by')->constrained('users');
            $table->string('recipient', 20);
            $table->foreignId('teacher_user_id')->nullable()->constrained('users');
            $table->string('reason', 300);
            $table->string('preferred_time', 100)->nullable();
            $table->string('status', 20)->default('open');
            $table->foreignId('called_by')->nullable()->constrained('users');
            $table->timestamp('called_at')->nullable();
            $table->string('outcome_note', 500)->nullable();
            $table->timestamps();

            // The office's and a teacher's lists: open first, newest first.
            $table->index(['school_id', 'status', 'created_at']);
            $table->index(['teacher_user_id', 'status']);
            $table->index(['student_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('call_requests');
    }
};
