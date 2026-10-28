<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F3 "Collection & receipts" (docs/fees.md): money the
 * office takes against what students owe.
 *
 * - `fee_receipts` - one payment taken from one student, with its number
 *   (`RCPT-2026-27-00001`), date, amount, mode and who took it. A wrong one
 *   is `cancelled` with a reason, never deleted: it keeps its number and its
 *   allocations, and the dues it paid go back to owing. The academic year is
 *   the one whose dates contain `receipt_date`; the number belongs to it.
 * - `fee_receipt_allocations` - how much of a receipt went to which due.
 *   They add up to the receipt's amount. A due that money was taken against
 *   cannot be deleted (restrict).
 * - `fee_receipt_sequences` - the last number used, per school and academic
 *   year. Locked (SELECT ... FOR UPDATE) inside the payment's transaction,
 *   so two clerks saving at the same moment get consecutive numbers and a
 *   failed save leaves no gap.
 *
 * Fees run on the Python backend only; the tables are created here because
 * Laravel's migrations own the schema until the cutover, as for Payroll.
 * Every amount is DECIMAL(12,2) beside a currency_code (CLAUDE.md rule 5),
 * copied from the dues the receipt pays.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fee_receipts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('academic_year_id')->constrained();
            $table->string('receipt_number', 40);
            $table->date('receipt_date');
            $table->decimal('amount', 12, 2);
            $table->char('currency_code', 3);

            // What the student owed in this currency just before this
            // payment, so a reprint months later shows the same figures.
            // Owed after = balance_before - amount.
            $table->decimal('balance_before', 12, 2)->default(0);

            // cash, bank_transfer, upi, cheque, card, online_transfer.
            $table->string('payment_mode', 20);

            // Cheque number, UTR, card slip. Required for a cheque.
            $table->string('reference', 100)->nullable();
            $table->string('note', 500)->nullable();
            $table->foreignId('received_by')->nullable()->constrained('users')->nullOnDelete();

            // `valid` or `cancelled`.
            $table->string('status', 20)->default('valid');
            $table->timestamp('cancelled_at')->nullable();
            $table->foreignId('cancelled_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('cancel_reason', 500)->nullable();

            // When the PDF was last emailed to the guardian.
            $table->timestamp('emailed_at')->nullable();
            $table->timestamps();

            $table->unique(['school_id', 'receipt_number'], 'fee_receipts_school_number_unique');
            $table->index(['school_id', 'receipt_date'], 'fee_receipts_school_date_index');
            $table->index('student_id', 'fee_receipts_student_index');
        });

        Schema::create('fee_receipt_allocations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('fee_receipt_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_fee_due_id')->constrained()->restrictOnDelete();
            $table->decimal('amount', 12, 2);
            $table->timestamps();

            $table->unique(['fee_receipt_id', 'student_fee_due_id'], 'fee_receipt_allocations_receipt_due_unique');
        });

        Schema::create('fee_receipt_sequences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_year_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('last_number')->default(0);
            $table->timestamps();

            $table->unique(['school_id', 'academic_year_id'], 'fee_receipt_sequences_school_year_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fee_receipt_sequences');
        Schema::dropIfExists('fee_receipt_allocations');
        Schema::dropIfExists('fee_receipts');
    }
};
