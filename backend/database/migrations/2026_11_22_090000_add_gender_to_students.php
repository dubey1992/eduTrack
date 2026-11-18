<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A student's gender (docs/dashboard.md, decided 2026-11-18), for the
 * dashboard's boys and girls counts.
 *
 * `male`, `female` or `other`, and null when the school has not said - every
 * student already on the roll starts as null, and the dashboard counts them
 * as "other or not given" so boys, girls and the rest always add up to the
 * total. Not indexed: it is only ever counted within one school's students,
 * which `school_id` already narrows.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->string('gender', 10)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->dropColumn('gender');
        });
    }
};
