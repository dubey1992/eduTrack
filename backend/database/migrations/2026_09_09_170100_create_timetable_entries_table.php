<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('timetable_entries', function (Blueprint $table) {
            $table->id();
            // Snapshotted directly rather than derived through
            // class_section_id every query, same reasoning as
            // StaffAttendance::school_id.
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->constrained()->cascadeOnDelete();
            $table->foreignId('period_id')->constrained()->cascadeOnDelete();
            $table->string('day_of_week');
            $table->foreignId('subject_id')->constrained()->cascadeOnDelete();
            $table->foreignId('teacher_id')->constrained('users')->cascadeOnDelete();
            $table->timestamps();

            // One subject/teacher per class section per day per period -
            // the DB-level twin of TimetableService's class-section-conflict
            // business rule.
            $table->unique(['class_section_id', 'period_id', 'day_of_week']);
            $table->index('school_id');
            $table->index(['teacher_id', 'day_of_week', 'period_id']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('timetable_entries');
    }
};
