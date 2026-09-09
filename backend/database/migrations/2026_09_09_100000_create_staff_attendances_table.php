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
        Schema::create('staff_attendances', function (Blueprint $table) {
            $table->id();
            // Snapshotted directly rather than derived through
            // staff_profile_id -> school every query, same reasoning as
            // Attendance::school_id (see that migration's comment).
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('staff_profile_id')->constrained()->cascadeOnDelete();
            $table->date('attendance_date');
            $table->string('status');
            $table->time('check_in')->nullable();
            $table->time('check_out')->nullable();
            $table->string('remarks', 255)->nullable();
            $table->foreignId('marked_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            // One status per staff member per day - the DB-level twin of
            // the ATTENDANCE_ALREADY_SUBMITTED business rule enforced in
            // StaffAttendanceService.
            $table->unique(['staff_profile_id', 'attendance_date']);
            $table->index('school_id');
            $table->index('attendance_date');
            $table->index('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('staff_attendances');
    }
};
