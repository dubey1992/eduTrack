<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One run of a class promotion (docs/promotion.md).
 *
 * A promotion moves a whole section at once, and every row it writes - the
 * closed enrollments, the new ones, the repointed students - belongs to one
 * intended act. This table is that act: who ran it, when, from where to
 * where, and how many students each outcome applied to.
 *
 * The counts are stored rather than derived. They are what the batch was
 * when it ran, and a count worked out later would drift the moment a child
 * is moved by hand afterwards - which is exactly the correction the product
 * expects somebody to make.
 *
 * `to_class_section_id` is nullable because a class with nothing above it
 * graduates: the batch is real and there is no section to land in.
 *
 * The two columns on `student_enrollments` arrive here rather than with that
 * table, because until a batch existed there was nothing for them to name:
 * `promotion_batch_id` on every row a batch closed or created, and
 * `promoted_from_enrollment_id` on a new row, pointing at the year it came
 * from. Together they answer "what did this run do" and "where did this
 * child come from" without either question needing a guess.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('promotion_batches', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('from_academic_year_id')->constrained('academic_years')->cascadeOnDelete();
            $table->foreignId('to_academic_year_id')->constrained('academic_years')->cascadeOnDelete();
            $table->foreignId('from_class_section_id')->constrained('class_sections')->cascadeOnDelete();
            // Null when every student graduated: there was nowhere to land.
            $table->foreignId('to_class_section_id')->nullable()->constrained('class_sections')->nullOnDelete();
            $table->unsignedInteger('promoted_count')->default(0);
            $table->unsignedInteger('retained_count')->default(0);
            $table->unsignedInteger('graduated_count')->default(0);
            $table->unsignedInteger('left_count')->default(0);
            $table->foreignId('run_by')->constrained('users');
            $table->timestamp('run_at');
            $table->timestamps();

            $table->index('school_id');
            $table->index('from_academic_year_id');
            $table->index('to_academic_year_id');
            $table->index('from_class_section_id');
        });

        Schema::table('student_enrollments', function (Blueprint $table) {
            $table->foreignId('promotion_batch_id')
                ->nullable()
                ->after('status')
                ->constrained('promotion_batches')
                ->nullOnDelete();
            $table->foreignId('promoted_from_enrollment_id')
                ->nullable()
                ->after('promotion_batch_id')
                ->constrained('student_enrollments')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('student_enrollments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('promoted_from_enrollment_id');
            $table->dropConstrainedForeignId('promotion_batch_id');
        });

        Schema::dropIfExists('promotion_batches');
    }
};
