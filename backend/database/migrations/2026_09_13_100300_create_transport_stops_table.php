<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('transport_stops', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('route_id')->constrained('transport_routes')->cascadeOnDelete();
            $table->string('name', 100);
            $table->unsignedTinyInteger('sequence_number');
            $table->time('pickup_time')->nullable();
            $table->time('drop_time')->nullable();
            $table->timestamps();

            $table->unique(['route_id', 'sequence_number']);
            $table->unique(['route_id', 'name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transport_stops');
    }
};
