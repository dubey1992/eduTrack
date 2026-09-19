<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Transport gains the person on the bus and where things are (docs/maps.md).
 *
 * - transport_routes.attendant_user_id: the Bus Attendant who runs this
 *   route's trips. One attendant may cover several routes.
 * - transport_stops.latitude/longitude: where the stop is, as schools
 *   already record it (decimal 10,7, optional, set as a pair).
 * - transport_trip_events.client_id: the id the attendant's phone gave a
 *   mark it made offline. A mark sent twice - the phone could not tell
 *   whether the first send arrived - is recognised by it and recorded once.
 * - transport_trip_locations: the positions the phone of whoever runs a
 *   trip reports while it is in progress. Kept 30 days.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transport_routes', function (Blueprint $table) {
            $table->foreignId('attendant_user_id')->nullable()->after('driver_id')
                ->constrained('users')->nullOnDelete();
        });

        Schema::table('transport_stops', function (Blueprint $table) {
            $table->decimal('latitude', 10, 7)->nullable()->after('drop_time');
            $table->decimal('longitude', 10, 7)->nullable()->after('latitude');
        });

        Schema::table('transport_trip_events', function (Blueprint $table) {
            $table->string('client_id', 64)->nullable()->after('note');
            $table->unique(['trip_id', 'client_id']);
        });

        Schema::create('transport_trip_locations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained('transport_trips')->cascadeOnDelete();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            // Metres, as the phone reports it; a point worse than 100 m is refused.
            $table->decimal('accuracy_m', 7, 2)->nullable();
            $table->decimal('speed_mps', 6, 2)->nullable();
            $table->decimal('heading', 5, 2)->nullable();
            $table->timestamp('recorded_at');
            $table->foreignId('recorded_by')->constrained('users');
            $table->timestamps();

            $table->index(['trip_id', 'recorded_at']);
            $table->index('recorded_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transport_trip_locations');

        Schema::table('transport_trip_events', function (Blueprint $table) {
            $table->dropUnique(['trip_id', 'client_id']);
            $table->dropColumn('client_id');
        });

        Schema::table('transport_stops', function (Blueprint $table) {
            $table->dropColumn(['latitude', 'longitude']);
        });

        Schema::table('transport_routes', function (Blueprint $table) {
            $table->dropConstrainedForeignId('attendant_user_id');
        });
    }
};
