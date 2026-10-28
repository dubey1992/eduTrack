<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F5 "Reminders, reports and dashboard" (docs/fees.md):
 * which guardians the automatic fee reminders have already reached.
 *
 * `send_fee_reminders` runs hourly, because schools keep their own
 * timezones. One guardian gets at most one reminder of each kind - `upcoming`
 * (the school's `reminder_days_before` days ahead of a due date) or `overdue`
 * (the first day a due is overdue) - per school-local day, listing every due
 * of every one of their children. This row is written in the same
 * transaction as the messages, and the unique key is what makes the second
 * run of the day send nothing, even when two runs overlap.
 *
 * `guardian_key` is how siblings are told apart from strangers: the
 * guardian's mobile number with everything but the digits taken out
 * (`m:919812345678`), else their email in lower case (`e:...`), else the
 * one student (`s:42`). `student_ids` is the comma-separated ids of the
 * students the message named - a record, never queried by.
 *
 * Fees run on the Python backend only; the table is created here because
 * Laravel's migrations own the schema until the cutover, as for Payroll.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fee_reminder_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('guardian_key', 120);

            // `upcoming` or `overdue`.
            $table->string('kind', 20);

            // The school-local day the reminder was for.
            $table->date('reminder_date');

            // No default: MySQL refuses one on TEXT.
            $table->text('student_ids')->nullable();
            $table->unsignedInteger('dues_count')->default(0);
            $table->timestamp('created_at')->nullable();

            $table->unique(
                ['school_id', 'guardian_key', 'kind', 'reminder_date'],
                'fee_reminder_logs_guardian_day_unique'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fee_reminder_logs');
    }
};
