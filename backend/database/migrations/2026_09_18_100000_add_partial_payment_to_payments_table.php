<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A payment could be marked Partial but had nowhere to record how much
     * had actually arrived, so nothing could say what was still owed.
     *
     * `amount` keeps its meaning - the agreed figure for this payment - and
     * `paid_amount` records what came in. What remains is the difference,
     * and is never stored: a derived figure that is also written down is a
     * figure that can disagree with itself.
     */
    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->decimal('paid_amount', 12, 2)->default(0)->after('amount');
            $table->timestamp('receipt_sent_at')->nullable()->after('status');
        });

        // A settled payment has had all of it paid. Everything else starts at
        // zero, including rows already marked Partial: the split was never
        // recorded, so claiming a figure here would be inventing one. Their
        // status is left alone rather than rewritten from a number this
        // migration does not know.
        DB::table('payments')->where('status', 'paid')->update(['paid_amount' => DB::raw('amount')]);
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->dropColumn(['paid_amount', 'receipt_sent_at']);
        });
    }
};
