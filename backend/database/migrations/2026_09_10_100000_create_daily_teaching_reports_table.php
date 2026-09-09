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
        Schema::create('daily_teaching_reports', function (Blueprint $table) {
            $table->id();
            // Snapshotted directly rather than derived through
            // timetable_entry_id every query, same reasoning as
            // StaffAttendance::school_id.
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('timetable_entry_id')->constrained()->cascadeOnDelete();
            // Also snapshotted from timetable_entries.teacher_id at creation
            // time - who actually filed the report never changes even if
            // the timetable entry's assigned teacher is reassigned later.
            $table->foreignId('teacher_id')->constrained('users')->cascadeOnDelete();
            $table->date('report_date');
            $table->string('topic_taught', 255);
            $table->string('homework', 500)->nullable();
            $table->string('remarks', 500)->nullable();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();

            // One report per scheduled occurrence - the DB-level twin of
            // the TEACHING_REPORT_ALREADY_SUBMITTED business rule enforced
            // in DailyTeachingReportService.
            $table->unique(['timetable_entry_id', 'report_date']);
            $table->index('school_id');
            $table->index(['teacher_id', 'report_date']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('daily_teaching_reports');
    }
};
