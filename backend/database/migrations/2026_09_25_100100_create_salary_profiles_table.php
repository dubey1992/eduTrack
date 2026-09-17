<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What an employee is paid each month: a basic salary, and the named earning
 * and deduction components on top of it. See docs/payroll.md.
 *
 * Fixed amounts the school enters - no tax or statutory formula, because
 * schools are in different countries. Payroll runs on the Python backend
 * only; the table is created here because Laravel's migrations own the schema
 * until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('salary_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();

            // One salary per employee.
            $table->foreignId('staff_profile_id')->unique()->constrained()->cascadeOnDelete();

            // Monthly, before pro-rating for attendance.
            $table->decimal('basic_salary', 12, 2);

            // The school's currency when the salary was saved - CLAUDE.md rule 5.
            $table->char('currency_code', 3);

            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index('school_id');
        });

        Schema::create('salary_components', function (Blueprint $table) {
            $table->id();
            $table->foreignId('salary_profile_id')->constrained()->cascadeOnDelete();

            // `earning` or `deduction`.
            $table->string('type', 16);
            $table->string('name', 100);

            // Monthly, before pro-rating.
            $table->decimal('amount', 12, 2);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            // "House rent" once as an earning; a deduction may share a name.
            $table->unique(['salary_profile_id', 'type', 'name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('salary_components');
        Schema::dropIfExists('salary_profiles');
    }
};
