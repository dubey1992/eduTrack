<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F6 "Credit balance" (docs/fees.md): money a student
 * paid that nothing is owed against yet, held on their account instead of
 * being refused or lost.
 *
 * One row per movement, never edited or deleted; a student's credit in a
 * currency is the sum of `amount` over their rows in it. In: `released` (an
 * installment paid ahead that stopped applying - a route or class change,
 * leaving, a fee cut - gives its money back), `overpaid` (a receipt that paid
 * more than was owed), `returned` (credit taken back off an installment it
 * had paid, when a cancelled receipt needed it). Out, as negative amounts:
 * `applied` (credit paying an installment), `refunded` (money handed back to
 * the family), `reversed` (a cancelled receipt taking back the credit it had
 * made).
 *
 * `student_fee_due_id` is the installment a released, applied or returned
 * row is about; `fee_receipt_id` the receipt an overpaid or reversed row is
 * about. A refund carries how the money went back, as a receipt carries how
 * it came in.
 *
 * `fee_receipts.credit_amount` is the part of a receipt held as credit:
 * a receipt's allocations add up to its amount less this.
 *
 * Fees run on the Python backend only; the table is created here because
 * Laravel's migrations own the schema until the cutover, as for Payroll.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('student_fee_credits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->string('currency_code', 3);

            // released | overpaid | returned | applied | refunded | reversed
            $table->string('kind', 20);

            // Signed: what the row adds to the credit, or takes off it.
            $table->decimal('amount', 12, 2);

            $table->foreignId('student_fee_due_id')->nullable()->constrained('student_fee_dues')->nullOnDelete();
            $table->foreignId('fee_receipt_id')->nullable()->constrained('fee_receipts')->nullOnDelete();

            // The school-local day the movement happened.
            $table->date('entry_date');

            // A refund's how and why.
            $table->string('payment_mode', 20)->nullable();
            $table->string('reference', 100)->nullable();
            $table->string('note', 500)->nullable();

            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['student_id', 'currency_code'], 'student_fee_credits_student_currency_index');
            $table->index(['school_id', 'kind'], 'student_fee_credits_school_kind_index');
        });

        Schema::table('fee_receipts', function (Blueprint $table) {
            $table->decimal('credit_amount', 12, 2)->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('fee_receipts', function (Blueprint $table) {
            $table->dropColumn('credit_amount');
        });

        Schema::dropIfExists('student_fee_credits');
    }
};
