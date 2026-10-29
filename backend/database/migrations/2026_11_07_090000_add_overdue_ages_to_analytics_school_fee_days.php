<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Analytics A5 (docs/analytics.md): how old what is overdue is, recorded
 * nightly with the rest of the fee snapshot.
 *
 * The outstanding-fees report splits overdue money into 1-30, 31-60 and 61+
 * days past due as at a day, but only as at today: each due keeps only what
 * has been paid so far. So, like the totals beside them, the three ages are
 * written down every night, and the "overdue by age" chart starts from the
 * first night they were. Existing rows read 0 for days before this column
 * existed - which the chart never shows, since it reads only nights that
 * recorded ages (a row carries `ages_recorded`).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('analytics_school_fee_days', function (Blueprint $table) {
            $table->decimal('overdue_0_30', 12, 2)->default(0);
            $table->decimal('overdue_31_60', 12, 2)->default(0);
            $table->decimal('overdue_61_plus', 12, 2)->default(0);
            $table->boolean('ages_recorded')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('analytics_school_fee_days', function (Blueprint $table) {
            $table->dropColumn(['overdue_0_30', 'overdue_31_60', 'overdue_61_plus', 'ages_recorded']);
        });
    }
};
