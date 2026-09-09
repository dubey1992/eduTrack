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
        Schema::create('syllabus_topic_progress', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('syllabus_topic_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->constrained()->cascadeOnDelete();
            $table->foreignId('completed_by')->constrained('users')->cascadeOnDelete();
            $table->timestamp('completed_at');
            $table->timestamps();

            // A row's existence IS "complete" for that topic in that class
            // section - marking incomplete deletes the row rather than
            // toggling a flag, same pattern as StaffLeave/Attendance history.
            // Explicit short name - the auto-generated one exceeds MySQL's
            // 64-character identifier limit.
            $table->unique(['syllabus_topic_id', 'class_section_id'], 'syllabus_progress_topic_section_unique');
            $table->index('school_id');
            $table->index('class_section_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('syllabus_topic_progress');
    }
};
