<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fees taken at the counter while the school's internet was down
 * (docs/offline-web.md, O4, decided 2026-11-28).
 *
 * The web app on a trusted computer takes cash or a cheque against the dues
 * it kept, hands the family a provisional receipt numbered
 * P-<computer>-<n>, and sends the payment when the line is back. The server
 * then makes the real receipt - or, when the dues were paid meanwhile or the
 * day's books are closed, keeps the payment here for an Accountant or School
 * Admin to settle.
 *
 * - client_id: the id the computer gave the payment, so sending it twice
 *   records it once (unique per school)
 * - allocations: the dues the counter chose, [{due_id, amount}], as sent
 * - status: receipted | to_settle | credited | refunded
 * - problem: why it could not become a receipt on arrival
 * - fee_receipt_id: the real receipt it became (receipted, credited)
 * - refund_mode / refund_reference / settle_note: how a refund went back
 *
 * Written by the Python backend only. Never deleted.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('offline_fee_payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('student_id')->constrained();
            $table->string('client_id', 64);
            $table->string('provisional_number', 40);
            $table->date('receipt_date');
            $table->decimal('amount', 12, 2);
            $table->string('currency_code', 3);
            $table->string('payment_mode', 20);
            $table->string('reference', 100)->nullable();
            $table->string('note', 500)->nullable();
            $table->json('allocations')->nullable();
            $table->foreignId('taken_by')->nullable()->constrained('users');
            $table->timestamp('taken_at')->nullable();
            $table->string('status', 20)->default('to_settle');
            $table->string('problem', 1000)->nullable();
            $table->foreignId('fee_receipt_id')->nullable()->constrained();
            $table->foreignId('settled_by')->nullable()->constrained('users');
            $table->timestamp('settled_at')->nullable();
            $table->string('settle_note', 500)->nullable();
            $table->string('refund_mode', 20)->nullable();
            $table->string('refund_reference', 100)->nullable();
            $table->timestamps();

            $table->unique(['school_id', 'client_id']);
            $table->index(['school_id', 'status']);
            $table->index('student_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('offline_fee_payments');
    }
};
