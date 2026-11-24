<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Attendance warnings to parents (docs/mobile-apps-review.md, M8, 5.4,
 * decided 2026-11-24): a child whose attendance fell below the school's
 * early-warning line, and when the family was told.
 *
 * One row per drop: written when the family is told, closed (`cleared_at`)
 * when attendance has come back up to the line. While a row is open nothing
 * more is sent - "once per drop", even across restarts. `rate` and `line`
 * are what the message said, kept as they were.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendance_warnings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->decimal('rate', 5, 1);
            $table->unsignedTinyInteger('line');
            $table->timestamp('warned_at');
            $table->timestamp('cleared_at')->nullable();
            $table->timestamps();

            // "Is there an open warning for this child?" is the one question asked.
            $table->index(['student_id', 'cleared_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_warnings');
    }
};
