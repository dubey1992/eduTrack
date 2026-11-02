<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Breaks in the school day - a short break, lunch, as many as a school
     * rings - shown in their place in every timetable.
     *
     * A table of their own rather than a kind of period, on purpose: periods
     * are counted by teaching reports, coverage, workload and the teacher's
     * day, and a break must never be counted as one by mistake.
     *
     * - day_shape: `full` or `half`, like periods - a half day rings its own
     *   bells and may have no lunch at all.
     * - name: what the school calls it ("Lunch break", "Short break").
     * - start_time, end_time: clock times in the school's own day.
     */
    public function up(): void
    {
        Schema::create('school_breaks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained('schools')->cascadeOnDelete();
            $table->string('day_shape', 8)->default('full');
            $table->string('name', 50);
            $table->time('start_time');
            $table->time('end_time');
            $table->timestamps();

            $table->index(['school_id', 'day_shape']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('school_breaks');
    }
};
