<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F2 "Dues" (docs/fees.md): what each student owes.
 *
 * - `students.admission_date` - the day a student joined, so a mid-year
 *   joiner is charged only the installments due on or after it. Optional:
 *   when empty, the school-local date the record was created stands in.
 * - `student_fee_dues` - one line on a student's account: one installment of
 *   one published fee. Never typed by anybody; the application creates,
 *   revives, re-prices and cancels them from the published fees, the
 *   student's class for the year and their bus route
 *   (school/fees/dues.py). A due is never deleted: a fee that no longer
 *   applies is `cancelled` with a reason, and anything already due stays
 *   owed. `discount_amount` and `paid_amount` stay 0 until discounts (F4) and
 *   payments (F3) arrive.
 *
 * One due per student per installment (the unique key), which is also what
 * makes charging idempotent: a cancelled due is revived, never duplicated.
 * The installment is restricted rather than cascaded - an installment that
 * students have been charged cannot quietly disappear, so the application
 * edits a published fee's installments in place and refuses to remove one
 * that is still charged.
 *
 * Fees run on the Python backend only; the table is created here because
 * Laravel's migrations own the schema until the cutover, as for Payroll.
 * Every amount is DECIMAL(12,2) beside a currency_code (CLAUDE.md rule 5),
 * copied from the fee when the due is created.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->date('admission_date')->nullable()->after('roll_number');
        });

        Schema::create('student_fee_dues', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('academic_year_id')->constrained();
            $table->foreignId('fee_structure_id')->constrained();
            $table->foreignId('fee_installment_id')->constrained()->restrictOnDelete();
            $table->foreignId('fee_head_id')->constrained();

            // "Tuition - April 2026": the head and installment as they were
            // named when the student was charged.
            $table->string('label', 130);
            $table->date('due_date');
            $table->decimal('amount', 12, 2);
            $table->decimal('discount_amount', 12, 2)->default(0);
            $table->decimal('paid_amount', 12, 2)->default(0);

            // The fee's currency - rule 5.
            $table->char('currency_code', 3);

            // `pending`, `partial`, `paid`, `waived` or `cancelled`.
            $table->string('status', 20)->default('pending');

            // `class_changed`, `route_changed`, `left` or `fee_changed`.
            $table->string('cancelled_reason', 30)->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->timestamps();

            // Named, so neither runs near MySQL's 64-character limit.
            $table->unique(['student_id', 'fee_installment_id'], 'student_fee_dues_student_installment_unique');
            $table->index(['school_id', 'status', 'due_date'], 'student_fee_dues_school_status_due_index');
            $table->index(['student_id', 'academic_year_id'], 'student_fee_dues_student_year_index');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('student_fee_dues');

        Schema::table('students', function (Blueprint $table) {
            $table->dropColumn('admission_date');
        });
    }
};
