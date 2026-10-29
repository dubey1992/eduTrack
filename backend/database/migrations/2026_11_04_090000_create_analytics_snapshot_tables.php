<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Analytics A1 (docs/analytics.md): a nightly record of the few figures the
 * database cannot rebuild for a past day.
 *
 * Almost every measure analytics charts is already stored with its own date
 * (attendance marks, receipts, marks, trips, topic completions) and is
 * counted from those. Two are not:
 *
 * - **How many students and staff a school had.** A student who leaves has
 *   no leaving date, so last March's roll cannot be counted today.
 * - **What was owed.** Each fee due keeps only what has been paid so far, so
 *   "outstanding at the end of March" would quietly count April's payments.
 *
 * So `record_analytics_snapshots` writes them down once a day, per school.
 * One row per school per day (per currency, for money - amounts are never
 * mixed across currencies), unique, so a second run on the same day replaces
 * rather than adds. Nothing reads these rows except analytics; deleting them
 * loses history, never data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('analytics_school_days', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained('schools')->cascadeOnDelete();

            // The school's own calendar day, not UTC's.
            $table->date('snapshot_date');
            $table->unsignedInteger('active_students');
            $table->unsignedInteger('active_staff');
            $table->timestamps();

            $table->unique(['school_id', 'snapshot_date']);
        });

        Schema::create('analytics_school_fee_days', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained('schools')->cascadeOnDelete();
            $table->date('snapshot_date');
            $table->char('currency_code', 3);

            // Due on or before the day and not yet paid, discounts taken off.
            $table->decimal('outstanding', 12, 2);

            // The part of it whose due date had already passed.
            $table->decimal('overdue', 12, 2);
            $table->timestamps();

            // Named, because the generated name is 70 characters and MySQL
            // refuses any over 64 (PostgreSQL silently cuts it to 63).
            $table->unique(['school_id', 'snapshot_date', 'currency_code'], 'analytics_fee_days_school_date_currency_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('analytics_school_fee_days');
        Schema::dropIfExists('analytics_school_days');
    }
};
