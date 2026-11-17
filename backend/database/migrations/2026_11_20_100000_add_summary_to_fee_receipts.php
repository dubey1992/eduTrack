<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The classic printed receipt's money summary, frozen when the payment is
 * taken (docs/document-styles.md, decided 2026-11-17).
 *
 * A school's printed receipt book reads: the month-wise fee lines, then Old
 * Fee, Discount, Late Fee, Total Amount, Back Dues, "Net Amount Till
 * <month>", Paid and Dues. None of those can be worked out later without
 * recalculating history - a concession given next month changes a due's
 * discount, a reconcile changes what is owed - so each is written once, at
 * the payment, and printed from the row for ever after.
 *
 * - fee_receipts.summary_*: null on receipts recorded before this, which
 *   print the figures they always had (owed before, paid, still owed).
 *   summary_till is the installment the summary runs to ("January 2026").
 * - fee_receipt_allocations.charge_amount: the fee line's full charge as it
 *   stood at the payment, for the classic receipt's Amount column.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('fee_receipts', function (Blueprint $table) {
            $table->decimal('summary_total', 12, 2)->nullable();
            $table->decimal('summary_discount', 12, 2)->nullable();
            $table->decimal('summary_late_fee', 12, 2)->nullable();
            $table->decimal('summary_paid_earlier', 12, 2)->nullable();
            $table->decimal('summary_back_dues', 12, 2)->nullable();
            $table->decimal('summary_old_fee', 12, 2)->nullable();
            $table->decimal('summary_net', 12, 2)->nullable();
            $table->string('summary_till', 80)->nullable();
        });

        Schema::table('fee_receipt_allocations', function (Blueprint $table) {
            $table->decimal('charge_amount', 12, 2)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('fee_receipt_allocations', function (Blueprint $table) {
            $table->dropColumn('charge_amount');
        });

        Schema::table('fee_receipts', function (Blueprint $table) {
            $table->dropColumn([
                'summary_total', 'summary_discount', 'summary_late_fee', 'summary_paid_earlier',
                'summary_back_dues', 'summary_old_fee', 'summary_net', 'summary_till',
            ]);
        });
    }
};
