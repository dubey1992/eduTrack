<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where an employee's pay goes, printed on their payslip (docs/pdf-design.md,
 * phase 2): the bank, the account, the branch code and their tax ID - all
 * optional, all set by whoever manages payroll on the Salaries screen.
 *
 * `bank_account_number` is encrypted at rest (school/crypto.py, the same key
 * that guards a school's messaging credentials), so TEXT: the ciphertext is
 * longer than any account number. Only its last four digits ever leave the
 * server - on the screen, the payslip and the audit trail alike.
 *
 * `bank_branch_code` is whatever the country uses to find the branch: an IFSC
 * in India, a sort code, a routing number. `tax_id` likewise: a PAN, a TIN.
 *
 * Payroll runs on the Python backend only; the columns are added here because
 * Laravel's migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salary_profiles', function (Blueprint $table) {
            $table->string('bank_name', 100)->nullable();
            $table->text('bank_account_number')->nullable();
            $table->string('bank_branch_code', 30)->nullable();
            $table->string('tax_id', 30)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('salary_profiles', function (Blueprint $table) {
            $table->dropColumn(['bank_name', 'bank_account_number', 'bank_branch_code', 'tax_id']);
        });
    }
};
