<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F1 "Fee Set-up" (docs/fees.md): what a school
 * charges, before anybody is charged it.
 *
 * - `fee_heads` - the school's fee types: Tuition, Admission, Exam... One,
 *   Transport (`is_transport`), exists in every school and carries the bus
 *   route fees; the application creates it and refuses to rename, retire or
 *   delete it. Names are unique per school without regard to case - the
 *   unique key below is case-sensitive on PostgreSQL, so the application
 *   checks the case-blind rule itself.
 * - `fee_structures` - one fee for one academic year: either a class's fee
 *   for one head, or a bus route's Transport fee. Exactly one of
 *   `school_class_id` and `transport_route_id` is set (checked by the
 *   application; a CHECK constraint would be the one MySQL/PostgreSQL
 *   difference this schema avoids). A draft until published.
 * - `fee_installments` - how a structure's amount is split, each with its own
 *   due date. They add up to the structure's amount, exactly.
 *
 * Fees run on the Python backend only; the tables are created here because
 * Laravel's migrations own the schema until the cutover, as for Payroll.
 * Every amount is DECIMAL(12,2) beside a currency_code (CLAUDE.md rule 5),
 * copied from the school when the structure is created.
 *
 * Classes, routes and academic years are not cascaded: deleting one that
 * has fees set up for it is refused by the application with a sentence,
 * because a school's fee book disappearing with a class is not something
 * anybody means to do.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fee_heads', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);

            // The one head bus route fees hang off. Never renamed or retired.
            $table->boolean('is_transport')->default(false);

            // Retired heads stay for the fees already set up with them, and
            // cannot be used for new ones.
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['school_id', 'name']);
            $table->index('school_id');
        });

        Schema::create('fee_structures', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('academic_year_id')->constrained();

            // Exactly one of these two.
            $table->foreignId('school_class_id')->nullable()->constrained();
            $table->foreignId('transport_route_id')->nullable()->constrained();

            $table->foreignId('fee_head_id')->constrained();
            $table->decimal('amount', 12, 2);

            // The school's currency when the fee was set up - rule 5.
            $table->char('currency_code', 3);

            // `monthly`, `quarterly`, `term`, `yearly` or `one_time`.
            $table->string('frequency', 20);

            // `draft` or `published`.
            $table->string('status', 20)->default('draft');
            $table->timestamp('published_at')->nullable();
            $table->foreignId('published_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            // One fee per head per class, and per head per route, each year.
            // A null class (a route fee) or a null route (a class fee) never
            // collides with another null, on either database. Named, because
            // the generated names run past MySQL's 64-character limit.
            $table->unique(['academic_year_id', 'school_class_id', 'fee_head_id'], 'fee_structures_year_class_head_unique');
            $table->unique(['academic_year_id', 'transport_route_id', 'fee_head_id'], 'fee_structures_year_route_head_unique');
            $table->index(['school_id', 'academic_year_id']);
        });

        Schema::create('fee_installments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('fee_structure_id')->constrained()->cascadeOnDelete();

            // 1-based position, assigned by the server.
            $table->unsignedSmallInteger('sequence');
            $table->string('label', 60);
            $table->date('due_date');
            $table->decimal('amount', 12, 2);
            $table->timestamps();

            $table->unique(['fee_structure_id', 'sequence']);
            $table->index('due_date');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fee_installments');
        Schema::dropIfExists('fee_structures');
        Schema::dropIfExists('fee_heads');
    }
};
