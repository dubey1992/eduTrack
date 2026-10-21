<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The school's list of bus stops - the places themselves (docs/maps.md).
 *
 * **Not the same thing as `transport_stops`**, and the difference is the
 * whole point. A row there is a *call*: this route stops here, fourth, at
 * 07:15. A row here is a *place*: the corner by the post office. Two routes
 * passing the same corner are two calls at one place, and before this table
 * they were two unrelated rows that happened to share coordinates - so a pin
 * dropped wrong had to be fixed once per route, and nobody could answer
 * "what stops do we serve?".
 *
 * **A position is required.** These are picked on a map; a stop nobody can
 * point to is not a stop. `transport_stops` keeps its nullable pair because
 * rows made before any of this exist and are still valid.
 *
 * **Name unique per school.** It is how people refer to a stop, and it is
 * also what keeps a route honest: `transport_stops` is unique on
 * (route, name), so two library stops can never collide on one route.
 *
 * Retired rather than deleted where it is in use - the same rule the rest of
 * transport follows, because a stop that trips have called at is history.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bus_stops', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            // Where it is. Seven decimal places is about a centimetre, which
            // is far more than a bus stop needs and the same precision the
            // rest of the product stores coordinates at.
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            // "Opposite the post office" - what somebody tells a parent on
            // the phone. Optional, because the name is often enough.
            $table->string('landmark', 100)->nullable();
            $table->string('status')->default('active');
            $table->timestamps();

            $table->unique(['school_id', 'name']);
            $table->index(['school_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bus_stops');
    }
};
