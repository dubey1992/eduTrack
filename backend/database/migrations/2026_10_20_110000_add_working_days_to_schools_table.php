<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The days a school actually runs (docs/holidays.md).
 *
 * The product is multi-nation - each school already carries its own currency
 * and its own timezone - but the week was Monday to Friday everywhere, in one
 * line of application code. A school in the Gulf running Sunday to Thursday
 * had attendance refused on Sundays, allowed on Fridays, and every
 * working-day denominator in every report computed against a week it does not
 * keep.
 *
 * Seven characters of '1' and '0', **Monday first**, which is Python's
 * `date.weekday()` order and PHP's `date('N') - 1`. A string rather than a
 * bitmask because it is read by two languages and by whoever opens the table:
 * '1111100' is a week anybody can check at a glance, and 124 is not.
 *
 * The default is the Monday-to-Friday week the application already assumed,
 * so adding this column changes no stored data and no behaviour until a
 * school is given its real week.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->char('working_days', 7)->default('1111100')->after('timezone');
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropColumn('working_days');
        });
    }
};
