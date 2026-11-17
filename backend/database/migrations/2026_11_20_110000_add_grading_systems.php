<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Grading systems (docs/document-styles.md, decided 2026-11-17): schools
 * grade in different ways, and a report card has to print the one each
 * school uses.
 *
 * - grade_scales.kind: `percentage` (bands by %, the card shows marks, % and
 *   grade - every scale until now), `gpa` (each band also carries grade
 *   points; the card adds each subject's points and an overall GPA) or
 *   `grades` (pre-primary and primary: no marks or % on the card, only each
 *   subject's grade and its description).
 * - grade_scales.gpa_multiplier: the school's own "percentage = GPA x 9.5",
 *   printed only when it is set. Never assumed.
 * - grade_bands.grade_point: the band's points on a GPA scale (A1 = 10.0,
 *   A = 4.0). Required for every band of a `gpa` scale, ignored elsewhere.
 * - grade_bands.description: what the grade means in words ("Outstanding",
 *   "First Division"), printed in the card's grading key.
 *
 * Every existing scale becomes `percentage`, which is what it already was.
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('grade_scales', function (Blueprint $table) {
            $table->string('kind', 20)->default('percentage');
            $table->decimal('gpa_multiplier', 5, 2)->nullable();
        });

        Schema::table('grade_bands', function (Blueprint $table) {
            $table->decimal('grade_point', 4, 2)->nullable();
            $table->string('description', 60)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('grade_bands', function (Blueprint $table) {
            $table->dropColumn(['grade_point', 'description']);
        });

        Schema::table('grade_scales', function (Blueprint $table) {
            $table->dropColumn(['kind', 'gpa_multiplier']);
        });
    }
};
