<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fee Management, step F2 "Dues" (docs/fees.md): since when a student has
 * been in their class, and on their bus route.
 *
 * Decided by the product owner on 2026-10-28: a student who moves class or
 * route mid-year is charged the new one's installments only from the day of
 * the move - never two classes, or two routes, for the same month.
 *
 * - `student_enrollments.class_since` - the school-local day the student
 *   moved into this enrollment's class, set only by a move within the year.
 *   Null for an enrollment that began with the year (admission, promotion):
 *   then the joining date is what counts.
 * - `student_transport_assignments.route_since` - the same for a change of
 *   bus route. Null for a student's first route.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('student_enrollments', function (Blueprint $table) {
            $table->date('class_since')->nullable();
        });

        Schema::table('student_transport_assignments', function (Blueprint $table) {
            $table->date('route_since')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('student_transport_assignments', function (Blueprint $table) {
            $table->dropColumn('route_since');
        });

        Schema::table('student_enrollments', function (Blueprint $table) {
            $table->dropColumn('class_since');
        });
    }
};
