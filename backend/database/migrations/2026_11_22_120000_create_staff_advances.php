<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Advances paid to staff, and their recovery from payslips
 * (docs/dashboard.md, D4, decided 2026-11-18).
 *
 * `staff_advances` - one row per advance: how much, when and how it was
 * paid, and how much is taken back each month from the month recovery
 * starts. Never deleted: a mistaken one is cancelled with a reason, and only
 * while nothing has been recovered.
 *
 * `payslip_lines.staff_advance_id` - the recovery itself is a deduction line
 * on the employee's payslip, pointing at the advance it repays. How much has
 * been recovered is the sum of those lines on finalized or paid runs - kept
 * on the payslips, never as a running total that could drift from them. A
 * draft's line is rebuilt with the draft, so nothing is counted twice.
 *
 * Money is DECIMAL(12,2) with the school's currency beside it (CLAUDE.md
 * rule 5). Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_advances', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained('schools');
            $table->foreignId('staff_profile_id')->constrained('staff_profiles');
            $table->decimal('amount', 12, 2);
            $table->char('currency_code', 3);
            $table->date('paid_on');
            $table->string('payment_mode', 32);
            $table->string('reference', 100)->nullable();
            // Taken off each payslip until it is repaid; the last month takes
            // only what is left.
            $table->decimal('monthly_recovery', 12, 2);
            // The first payroll month that recovers it - the 1st of a month.
            $table->date('recovery_starts');
            $table->string('reason', 500);
            // active or cancelled; "repaid" is worked out, never stored.
            $table->string('status', 20)->default('active');
            $table->foreignId('created_by')->nullable()->constrained('users');
            $table->timestamp('cancelled_at')->nullable();
            $table->foreignId('cancelled_by')->nullable()->constrained('users');
            $table->string('cancel_reason', 500)->nullable();
            $table->timestamps();

            $table->index(['school_id', 'status']);
            $table->index('staff_profile_id');
        });

        Schema::table('payslip_lines', function (Blueprint $table) {
            $table->foreignId('staff_advance_id')->nullable()->constrained('staff_advances');
        });
    }

    public function down(): void
    {
        Schema::table('payslip_lines', function (Blueprint $table) {
            $table->dropConstrainedForeignId('staff_advance_id');
        });

        Schema::dropIfExists('staff_advances');
    }
};
