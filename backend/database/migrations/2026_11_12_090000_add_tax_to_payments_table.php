<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Tax on a Super Admin payment (GST, VAT - whatever the school's country
     * charges), as a percentage of the services.
     *
     * - tax_rate: the percentage, 0 to 100, two decimals. 0 is no tax.
     * - tax_amount: what that comes to, worked out by the server from the
     *   payment's lines and rounded to the cent.
     *
     * payments.amount stays the figure the school owes: the services plus
     * the tax. Every existing payment had no tax, so both columns start at 0
     * and nothing about them changes.
     */
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->decimal('tax_rate', 5, 2)->default(0)->after('amount');
            $table->decimal('tax_amount', 12, 2)->default(0)->after('tax_rate');
        });
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->dropColumn(['tax_rate', 'tax_amount']);
        });
    }
};
