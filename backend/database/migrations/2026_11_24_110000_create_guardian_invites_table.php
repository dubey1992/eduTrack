<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A parent asking the school to add another guardian of their child
 * (docs/mobile-apps-review.md, M8, 8.5, decided 2026-11-24): the office
 * approves or declines; nobody sees a child's records until it does.
 *
 * On approval the guardian is linked exactly as the office links one by hand
 * (`guardian_student_id` is that link), with the same rights as any other;
 * the set-up code then goes out from the student's Guardians, as for any
 * guardian. A decided request is kept as the record of who asked and who
 * agreed.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('guardian_invites', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('requested_by')->constrained('users')->restrictOnDelete();
            $table->string('name', 150);
            $table->string('mobile', 20);
            $table->string('relationship', 20);
            $table->string('status', 20)->default('pending');
            $table->foreignId('decided_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('decided_at')->nullable();
            $table->foreignId('guardian_student_id')->nullable()->constrained('guardian_student')->nullOnDelete();
            $table->timestamps();

            // The office's list: a school's requests by status.
            $table->index(['school_id', 'status']);
            $table->index('student_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('guardian_invites');
    }
};
