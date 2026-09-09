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
        Schema::create('attendances', function (Blueprint $table) {
            $table->id();
            // Both reachable through class_section_id -> school_class, but
            // snapshotted directly (never trusted from the client - see
            // AttendanceService) so every school-scoped / year-scoped query
            // avoids a two-join walk, matching CLAUDE.md rule 9's explicit
            // school_id/academic_year_id indexing guidance.
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_year_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->constrained('class_sections')->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->date('attendance_date');
            $table->string('status');
            $table->string('remarks', 255)->nullable();
            // Who submitted/last edited this record - nullable so deleting a
            // teacher's account doesn't cascade into deleting attendance
            // history.
            $table->foreignId('marked_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            // One status per student per class per day - the DB-level twin
            // of the ATTENDANCE_ALREADY_SUBMITTED business rule enforced in
            // AttendanceService.
            $table->unique(['class_section_id', 'student_id', 'attendance_date']);
            $table->index('school_id');
            $table->index('academic_year_id');
            $table->index('student_id');
            $table->index('attendance_date');
            $table->index('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('attendances');
    }
};
