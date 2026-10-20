<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The route's legs, as text rather than a json column (docs/maps.md, M2).
 *
 * Django's `JSONField` assumes PostgreSQL's `jsonb`, and every json column
 * in this schema was built by Laravel as `json`. The two are not
 * interchangeable: `json` has no equality operator, so a route list that
 * counts with `distinct=True` fails outright, and Django's own lookups
 * generate `= 'null'::jsonb`, which `json` refuses.
 *
 * That mismatch is older and wider than this column - `audit_logs`,
 * `messages`, `module_settings`, `marketing_content` and `queued_jobs` all
 * have it - and changing them is its own piece of work. This column is a
 * day old and read in exactly one place, so it sidesteps the question: the
 * legs are a string the application encodes and decodes, which behaves the
 * same on MySQL and PostgreSQL and on anything either is replaced with.
 *
 * Dropped and recreated rather than altered: the column has existed for a
 * few hours and holds nothing anybody needs.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transport_routes', function (Blueprint $table) {
            $table->dropColumn('path_legs');
        });

        Schema::table('transport_routes', function (Blueprint $table) {
            $table->text('path_legs')->nullable()->after('path_duration_s');
        });
    }

    public function down(): void
    {
        Schema::table('transport_routes', function (Blueprint $table) {
            $table->dropColumn('path_legs');
        });

        Schema::table('transport_routes', function (Blueprint $table) {
            $table->json('path_legs')->nullable()->after('path_duration_s');
        });
    }
};
