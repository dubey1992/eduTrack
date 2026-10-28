<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F4 "Discounts, waivers and late fines" (docs/fees.md).
 *
 * - `fee_concessions` - a discount one student gets for one academic year:
 *   a fixed amount or a percentage, off one fee type (`fee_head_id`) or off
 *   every fee type when it is null (late fines are never discounted), with a
 *   reason. It comes off each installment of the matching fee types, and the
 *   application keeps every unpaid due's `discount_amount` in line with the
 *   active ones (school/fees/dues.py). Revoking keeps the row (`revoked_at`,
 *   `revoked_by`) and the dues go back to what they were.
 * - `student_fee_dues` gains:
 *   - `kind` - `installment` (one installment of a published fee, as F2
 *     charges them) or `late_fine` (school/fees/fines.py);
 *   - `fine_for_due_id` - on a fine, the installment due it is for. Unique,
 *     so the database itself keeps "one fine per installment, once".
 *     `nullOnDelete`: dues are never deleted, except a *cancelled* due whose
 *     installment is removed from a published fee - and a fine is money owed
 *     in its own right, so it outlives the line it was charged for rather
 *     than blocking that clean-up (restrict) or vanishing with it (cascade);
 *   - `waived_at`, `waived_by`, `waive_reason` - a due forgiven outright.
 *   - `fee_installment_id` and `fee_structure_id` become nullable: a fine has
 *     neither. The unique key on (student_id, fee_installment_id) keeps
 *     working, as NULLs never collide on MySQL or PostgreSQL.
 *
 * Fees run on the Python backend only; the tables are Laravel's until the
 * cutover, as for Payroll.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fee_concessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained();
            $table->foreignId('academic_year_id')->constrained();

            // Null: every fee type (late fines excepted).
            $table->foreignId('fee_head_id')->nullable()->constrained();

            // `fixed` (an amount off each installment) or `percent`.
            $table->string('kind', 10);

            // A fixed amount (> 0) or a percentage (> 0, at most 100).
            $table->decimal('value', 12, 2);
            $table->string('reason', 255);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('revoked_at')->nullable();
            $table->foreignId('revoked_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['student_id', 'academic_year_id'], 'fee_concessions_student_year_index');
            $table->index('school_id', 'fee_concessions_school_index');
        });

        Schema::table('student_fee_dues', function (Blueprint $table) {
            $table->string('kind', 20)->default('installment')->after('fee_head_id');
            $table->foreignId('fine_for_due_id')->nullable()->after('kind')
                ->constrained('student_fee_dues')->nullOnDelete();
            $table->timestamp('waived_at')->nullable()->after('cancelled_at');
            $table->foreignId('waived_by')->nullable()->after('waived_at')->constrained('users')->nullOnDelete();
            $table->string('waive_reason', 255)->nullable()->after('waived_by');

            $table->unique('fine_for_due_id', 'student_fee_dues_fine_for_due_unique');
        });

        // Laravel 11+ changes columns natively on both engines; every
        // attribute is restated, as `change()` requires. The foreign keys
        // stay where they are - only NOT NULL is dropped.
        Schema::table('student_fee_dues', function (Blueprint $table) {
            $table->unsignedBigInteger('fee_structure_id')->nullable()->change();
            $table->unsignedBigInteger('fee_installment_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        // Fines have no installment; they cannot survive the columns becoming
        // required again.
        DB::table('student_fee_dues')->where('kind', 'late_fine')->delete();

        Schema::table('student_fee_dues', function (Blueprint $table) {
            $table->unsignedBigInteger('fee_structure_id')->nullable(false)->change();
            $table->unsignedBigInteger('fee_installment_id')->nullable(false)->change();
        });

        Schema::table('student_fee_dues', function (Blueprint $table) {
            $table->dropForeign(['fine_for_due_id']);
            $table->dropUnique('student_fee_dues_fine_for_due_unique');
            $table->dropForeign(['waived_by']);
            $table->dropColumn(['kind', 'fine_for_due_id', 'waived_at', 'waived_by', 'waive_reason']);
        });

        Schema::dropIfExists('fee_concessions');
    }
};
