<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * When the guardians were told about this test's result (docs/assessments.md).
 *
 * Separate from `published_at` because the two answer different questions and
 * come apart in exactly the case that matters: a result is published, the
 * guardians are told, somebody reopens the test to fix one mark, and it is
 * published again. `published_at` is cleared by the reopen and set again by
 * the second publish; this column is not, so the second publish sends nothing
 * and no family gets the same result twice.
 *
 * Null therefore means "nobody has been told yet", not "not published" - a
 * test published while the school had messaging switched off keeps a null
 * here, which is the honest record of what happened.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('assessments', function (Blueprint $table) {
            $table->timestamp('results_announced_at')->nullable()->after('published_at');
        });
    }

    public function down(): void
    {
        Schema::table('assessments', function (Blueprint $table) {
            $table->dropColumn('results_announced_at');
        });
    }
};
