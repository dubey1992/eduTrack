<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Parent-teacher meetings booked from the Family app
 * (docs/mobile-apps-review.md, M12, 8.4, decided 2026-11-25).
 *
 * A School Admin creates the meeting day and picks the classes taking part
 * (ptm_meetings + ptm_meeting_sections). Each class teacher, or an admin,
 * opens slots for their class (ptm_slots). A parent books one slot per child
 * (ptm_bookings) and may move or cancel it until the end of the day before.
 *
 * - ptm_meetings.status: scheduled | cancelled
 * - ptm_meeting_sections.slots_opened_at: when the class's slots first opened,
 *   so the parents' "slots are open" message goes once
 * - ptm_slots.teacher_user_id: who meets the parents - the class teacher when
 *   the slots were opened, so a later change does not move a booked slot
 * - ptm_slots times are the school's own wall-clock times on meeting_date
 * - ptm_bookings: one per slot, one per child per meeting; cancelling removes
 *   the row (the audit log keeps the history)
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ptm_meetings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->string('title', 120);
            $table->date('meeting_date');
            $table->string('note', 300)->nullable();
            $table->string('status', 20)->default('scheduled');
            $table->foreignId('created_by')->nullable()->constrained('users');
            $table->timestamps();

            $table->index(['school_id', 'meeting_date']);
        });

        Schema::create('ptm_meeting_sections', function (Blueprint $table) {
            $table->id();
            $table->foreignId('ptm_meeting_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->constrained();
            $table->timestamp('slots_opened_at')->nullable();
            $table->timestamps();

            $table->unique(['ptm_meeting_id', 'class_section_id']);
            $table->index('class_section_id');
        });

        Schema::create('ptm_slots', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('ptm_meeting_id')->constrained()->cascadeOnDelete();
            $table->foreignId('class_section_id')->constrained();
            $table->foreignId('teacher_user_id')->nullable()->constrained('users');
            $table->time('starts_at');
            $table->time('ends_at');
            $table->timestamps();

            $table->unique(['ptm_meeting_id', 'class_section_id', 'starts_at']);
            $table->index('teacher_user_id');
        });

        Schema::create('ptm_bookings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('ptm_meeting_id')->constrained()->cascadeOnDelete();
            $table->foreignId('ptm_slot_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('booked_by')->constrained('users');
            $table->timestamps();

            $table->unique(['ptm_meeting_id', 'student_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ptm_bookings');
        Schema::dropIfExists('ptm_slots');
        Schema::dropIfExists('ptm_meeting_sections');
        Schema::dropIfExists('ptm_meetings');
    }
};
