<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A Super Admin payment could cover only one service. Now it can cover
     * several - Setup Fee, Annual Maintenance, Additional Service, and any
     * number of "other" fees the Super Admin names - each with its own amount,
     * on one payment and one receipt.
     *
     * - service: setup_fee, annual_maintenance, additional_service or other.
     * - name: what an "other" fee is for, as typed. Empty for the others,
     *   whose name is the service's own label.
     * - amount, currency_code: this line's figure, in the payment's currency
     *   (CLAUDE.md rule 5 - never an amount without its currency).
     * - position: the order the lines were entered, and the receipt prints.
     *
     * payments.amount stays: it is the sum of the lines, written by the same
     * save that writes them. payments.payment_type stays too, holding the
     * first line's service, so a filter or an old reader still has a value.
     *
     * Every existing payment gets one line - its own type and amount - so its
     * receipt reads exactly as it did.
     */
    public function up(): void
    {
        Schema::create('payment_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('payment_id')->constrained('payments')->cascadeOnDelete();
            $table->string('service', 50);
            $table->string('name', 100)->nullable();
            $table->decimal('amount', 12, 2);
            $table->char('currency_code', 3);
            $table->unsignedSmallInteger('position')->default(0);
            $table->timestamps();

            $table->index(['payment_id', 'position']);
            $table->index('service');
        });

        DB::table('payments')->orderBy('id')->chunkById(500, function ($payments) {
            $rows = [];

            foreach ($payments as $payment) {
                $rows[] = [
                    'payment_id' => $payment->id,
                    'service' => $payment->payment_type,
                    // An old "Other" payment never said what it was for.
                    'name' => $payment->payment_type === 'other' ? 'Other' : null,
                    'amount' => $payment->amount,
                    'currency_code' => $payment->currency_code,
                    'position' => 0,
                    'created_at' => $payment->created_at,
                    'updated_at' => $payment->updated_at,
                ];
            }

            DB::table('payment_items')->insert($rows);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payment_items');
    }
};
