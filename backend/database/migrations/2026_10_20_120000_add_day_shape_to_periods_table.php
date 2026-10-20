<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A full day's periods and a half day's (docs/holidays.md, H1).
 *
 * A school that runs a Saturday morning does not run the same bells on it:
 * the periods are shorter and there are fewer of them. Until now `periods`
 * was unique on (school_id, period_number) with no day in it at all, so a
 * forty-minute Saturday period could not be expressed.
 *
 * Two shapes rather than a set per weekday, because it is how schools
 * describe it and the freedom to give every day its own bells is a ragged
 * grid nobody asked for. A school needing "Saturday is PT only" uses the
 * half-day shape with one period in it.
 *
 * Every existing row is a full day's period, so a school that never uses
 * this is untouched - and (school_id, 'full', period_number) is exactly the
 * uniqueness that was there before.
 *
 * `schools.working_days` needs no migration: it is already char(7), and the
 * third state ('2' for a half day, beside '0' closed and '1' full) is a
 * widening of what that column may hold, not of the column.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('periods', function (Blueprint $table) {
            $table->string('day_shape', 8)->default('full')->after('period_number');
        });

        // The new index goes on before the old one comes off. MySQL requires
        // an index on a foreign key column, and (school_id, period_number)
        // is the only one `periods.school_id` has - so dropping it first
        // fails with errno 150 and leaves the table half-migrated.
        Schema::table('periods', function (Blueprint $table) {
            $table->unique(['school_id', 'day_shape', 'period_number']);
        });

        Schema::table('periods', function (Blueprint $table) {
            $table->dropUnique('periods_school_id_period_number_unique');
        });
    }

    public function down(): void
    {
        Schema::table('periods', function (Blueprint $table) {
            $table->unique(['school_id', 'period_number']);
        });

        Schema::table('periods', function (Blueprint $table) {
            $table->dropUnique(['school_id', 'day_shape', 'period_number']);
        });

        Schema::table('periods', function (Blueprint $table) {
            $table->dropColumn('day_shape');
        });
    }
};
