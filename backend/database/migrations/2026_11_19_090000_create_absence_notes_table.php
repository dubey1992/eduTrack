<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A parent telling the school their child will be away
 * (docs/parent-student-app.md, F5, "Absence notes").
 *
 * Sent from the Family app for days from today up to 30 days ahead, with a
 * reason and, if they have one, a photo of a doctor's note (re-encoded on the
 * server, kept in private storage, served only to staff who may see it).
 *
 * The note never marks the register: it shows beside the child on the
 * register for its days and in the class teacher's inbox, and the teacher
 * acknowledges it (decided 2026-11-17). The parent then sees "Seen by the
 * class teacher".
 *
 * - status: sent | acknowledged
 * - submitted_by: the family account that sent it
 * - acknowledged_by / acknowledged_at: the member of staff who saw it, and when
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('absence_notes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('submitted_by')->constrained('users');
            $table->date('start_date');
            $table->date('end_date');
            $table->string('reason', 500);
            $table->string('photo_path', 255)->nullable();
            $table->string('status', 20)->default('sent');
            $table->foreignId('acknowledged_by')->nullable()->constrained('users');
            $table->timestamp('acknowledged_at')->nullable();
            $table->timestamps();

            // The register asks "a note for this child on this day?"; the
            // teacher's list asks "notes not yet seen in my school".
            $table->index(['student_id', 'start_date', 'end_date']);
            $table->index(['school_id', 'status', 'start_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('absence_notes');
    }
};
