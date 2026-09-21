<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How a school turns a percentage into a grade (docs/assessments.md).
 *
 * A scale is a named set of bands - A1 is 91 to 100, and so on - and a
 * school may keep more than one, because a primary school's letters are
 * rarely the secondary school's. One of them is the default, which is what
 * an assessment gets when nobody chooses.
 *
 * A grade is never typed by a teacher. It is derived from the marks, and at
 * publish it is written onto the mark row, so moving a boundary later
 * cannot rewrite a result somebody has already been told about.
 *
 * The bands of one scale must cover 0 to 100 with no gap and no overlap.
 * That is checked in the service rather than here: a database constraint
 * cannot see the other rows of the set as they are being replaced, and a
 * half-saved scale would be worse than a late refusal.
 *
 * `is_failing` marks the bands that count as not passed. It is not always
 * the lowest one - a school can have two failing bands - so it is a flag
 * rather than a position.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('grade_scales', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 50); // "Secondary", "Primary".
            $table->boolean('is_default')->default(false); // One per school, kept by the service.
            $table->timestamps();

            $table->unique(['school_id', 'name']);
            $table->index(['school_id', 'is_default']);
        });

        Schema::create('grade_bands', function (Blueprint $table) {
            $table->id();
            $table->foreignId('grade_scale_id')->constrained()->cascadeOnDelete();
            $table->string('label', 10); // "A1", "Pass".
            $table->decimal('min_percentage', 5, 2); // 0.00 to 100.00, inclusive at both ends.
            $table->decimal('max_percentage', 5, 2);
            $table->boolean('is_failing')->default(false);
            $table->timestamps();

            $table->unique(['grade_scale_id', 'label']);
            $table->index(['grade_scale_id', 'min_percentage'], 'grade_bands_scale_min_index');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('grade_bands');
        Schema::dropIfExists('grade_scales');
    }
};
