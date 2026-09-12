<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One run of a route: today's morning pickup or afternoon drop
     * (decided 2026-09-10). The vehicle and driver are snapshotted so the
     * record stays true even if the route is re-assigned later.
     */
    public function up(): void
    {
        Schema::create('transport_trips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('route_id')->constrained('transport_routes')->restrictOnDelete();
            $table->foreignId('vehicle_id')->constrained('vehicles')->restrictOnDelete();
            $table->foreignId('driver_id')->constrained('drivers')->restrictOnDelete();
            $table->date('trip_date');
            $table->string('direction', 10);
            $table->string('status', 20)->default('in_progress');
            $table->foreignId('current_stop_id')->nullable()->constrained('transport_stops')->nullOnDelete();
            $table->foreignId('started_by')->constrained('users')->restrictOnDelete();
            $table->timestamp('started_at');
            $table->timestamp('ended_at')->nullable();
            $table->timestamps();

            $table->index(['route_id', 'trip_date', 'direction']);
            $table->index(['school_id', 'trip_date']);
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transport_trips');
    }
};
