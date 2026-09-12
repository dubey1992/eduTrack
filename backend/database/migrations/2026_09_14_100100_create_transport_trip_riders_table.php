<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The students expected on a trip, snapshotted from the route's
     * assignments when it starts. stop_name is copied so the record
     * survives the stop being renamed or removed later.
     */
    public function up(): void
    {
        Schema::create('transport_trip_riders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained('transport_trips')->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('stop_id')->nullable()->constrained('transport_stops')->nullOnDelete();
            $table->string('stop_name', 100);
            $table->unsignedTinyInteger('stop_sequence_number');
            $table->string('status', 20)->default('pending');
            $table->timestamp('boarded_at')->nullable();
            $table->timestamp('dropped_at')->nullable();
            $table->timestamps();

            $table->unique(['trip_id', 'student_id']);
            $table->index(['trip_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transport_trip_riders');
    }
};
