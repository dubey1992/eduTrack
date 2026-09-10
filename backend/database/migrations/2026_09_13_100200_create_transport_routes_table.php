<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A route carries its CURRENT vehicle and driver (decided 2026-09-10) -
     * a vehicle/driver serves at most one route at a time, hence the unique
     * indexes (MySQL allows many NULLs). Phase 15 trips snapshot who
     * actually drove.
     */
    public function up(): void
    {
        Schema::create('transport_routes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->foreignId('vehicle_id')->nullable()->constrained('vehicles')->restrictOnDelete();
            $table->foreignId('driver_id')->nullable()->constrained('drivers')->restrictOnDelete();
            $table->string('status', 20)->default('active');
            $table->timestamps();

            $table->unique(['school_id', 'name']);
            $table->unique('vehicle_id');
            $table->unique('driver_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transport_routes');
    }
};
