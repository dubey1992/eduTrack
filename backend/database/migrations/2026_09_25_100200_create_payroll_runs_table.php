<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One school's payroll for one month: draft, then finalized, then paid.
 * See docs/payroll.md.
 *
 * Payroll runs on the Python backend only; the tables are created here because
 * Laravel's migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payroll_runs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->unsignedSmallInteger('year');
            $table->unsignedTinyInteger('month');

            // `draft`, `finalized` or `paid`.
            $table->string('status', 16)->default('draft');

            // The school's currency when the run was generated - rule 5.
            $table->char('currency_code', 3);

            // The month's working days when last computed: weekdays less the
            // school's holidays.
            $table->unsignedSmallInteger('working_days');

            $table->foreignId('generated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('finalized_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('finalized_at')->nullable();

            // When the last payslip was paid.
            $table->timestamp('paid_at')->nullable();
            $table->timestamps();

            // One run per school per month.
            $table->unique(['school_id', 'year', 'month']);
            $table->index('status');
        });

        // A snapshot: once the run is finalized, nothing here is re-derived
        // from the employee or their salary, so a later raise never rewrites
        // a payslip somebody has already been given.
        Schema::create('payslips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('payroll_run_id')->constrained()->cascadeOnDelete();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('staff_profile_id')->constrained()->cascadeOnDelete();

            $table->string('employee_name');
            $table->string('employee_code', 30);
            $table->string('designation', 100)->nullable();
            $table->string('department_name')->nullable();
            $table->char('currency_code', 3);

            // Half days make these fractional.
            $table->decimal('working_days', 5, 1);
            $table->decimal('paid_days', 5, 1);
            $table->decimal('absent_days', 5, 1);
            $table->unsignedSmallInteger('half_days');

            // Working days nobody marked: counted as paid, shown so it is seen.
            $table->unsignedSmallInteger('unmarked_days');

            $table->decimal('gross_earnings', 12, 2);
            $table->decimal('total_deductions', 12, 2);

            // Never below zero; what deductions exceeded earnings by is kept.
            $table->decimal('net_pay', 12, 2);
            $table->decimal('shortfall', 12, 2)->default(0);

            // `unpaid` or `paid`.
            $table->string('status', 16)->default('unpaid');
            $table->date('paid_on')->nullable();
            $table->string('payment_mode', 32)->nullable();
            $table->string('payment_reference', 100)->nullable();
            $table->timestamp('emailed_at')->nullable();
            $table->timestamps();

            $table->unique(['payroll_run_id', 'staff_profile_id']);
            $table->index('staff_profile_id');
            $table->index('status');
        });

        Schema::create('payslip_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('payslip_id')->constrained()->cascadeOnDelete();

            // `earning` or `deduction`; `basic`, `component` or `adjustment`.
            $table->string('type', 16);
            $table->string('source', 16);
            $table->string('name', 100);

            // The monthly figure before pro-rating; null for an adjustment,
            // which is never pro-rated.
            $table->decimal('full_amount', 12, 2)->nullable();

            // What is paid or deducted this month.
            $table->decimal('amount', 12, 2);

            // Why - required for an adjustment.
            $table->string('note')->nullable();
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index('payslip_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payslip_lines');
        Schema::dropIfExists('payslips');
        Schema::dropIfExists('payroll_runs');
    }
};
