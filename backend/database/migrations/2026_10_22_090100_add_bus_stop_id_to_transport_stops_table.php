<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which place in the school's list this route stop is a call at
 * (docs/maps.md).
 *
 * **Nullable, and every row that exists today is null.** Stops were made
 * one route at a time long before there was a list to pick from, and those
 * rows are still correct - a route still stops there. They are one-offs,
 * and the product works with a mix.
 *
 * `nullOnDelete` rather than cascade: deleting a place must never delete a
 * route's call at it. In practice the service refuses to delete a place any
 * route uses at all, and names the routes; this is the database saying the
 * same thing in the only way it can.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transport_stops', function (Blueprint $table) {
            $table->foreignId('bus_stop_id')->nullable()->after('route_id')
                ->constrained('bus_stops')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('transport_stops', function (Blueprint $table) {
            $table->dropConstrainedForeignId('bus_stop_id');
        });
    }
};
