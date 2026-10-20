<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The road a route actually follows (docs/maps.md, M2).
 *
 * Straight lines between stops cross rivers and go the wrong way up
 * one-way streets, so the path is asked of Google's Routes API - once,
 * when the stops change, and never per view. That is the whole reason it
 * is a column rather than a request: a map that computed its own line
 * would bill a call for every administrator who opened it.
 *
 * - path_polyline: Google's encoded polyline for the whole run. Text
 *   rather than a geometry type, because the product must stay portable
 *   between MySQL and PostgreSQL (CLAUDE.md rule 9).
 * - path_distance_m / path_duration_s: the run, end to end. The duration
 *   is free-flowing traffic, which is what an unscheduled route is worth
 *   quoting; a live estimate is a per-refresh call and M3 does not make
 *   one.
 * - path_legs: each leg's distance and duration in order, which is what
 *   M3's "how far to the next stop" is computed from without asking
 *   Google again.
 * - path_status: none (never computed) / ok / stale (the stops changed
 *   and the job has not run) / failed (Google refused, and the map falls
 *   back to straight lines and offers to try again).
 * - path_failure_reason: why, in words an administrator can read.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transport_routes', function (Blueprint $table) {
            $table->text('path_polyline')->nullable()->after('status');
            $table->unsignedInteger('path_distance_m')->nullable()->after('path_polyline');
            $table->unsignedInteger('path_duration_s')->nullable()->after('path_distance_m');
            $table->json('path_legs')->nullable()->after('path_duration_s');
            $table->string('path_status', 20)->default('none')->after('path_legs');
            $table->string('path_failure_reason', 255)->nullable()->after('path_status');
            $table->timestamp('path_computed_at')->nullable()->after('path_failure_reason');
        });
    }

    public function down(): void
    {
        Schema::table('transport_routes', function (Blueprint $table) {
            $table->dropColumn([
                'path_polyline',
                'path_distance_m',
                'path_duration_s',
                'path_legs',
                'path_status',
                'path_failure_reason',
                'path_computed_at',
            ]);
        });
    }
};
