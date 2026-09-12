<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The trip timeline - every start/stop/board/drop/end as it happened.
     * Names are snapshotted so the timeline reads correctly years later;
     * Phase 16 (communication) will consume boarded/dropped events for
     * parent alerts.
     */
    public function up(): void
    {
        Schema::create('transport_trip_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('trip_id')->constrained('transport_trips')->cascadeOnDelete();
            $table->string('type', 20);
            $table->foreignId('stop_id')->nullable()->constrained('transport_stops')->nullOnDelete();
            $table->string('stop_name', 100)->nullable();
            $table->foreignId('student_id')->nullable()->constrained()->nullOnDelete();
            $table->string('student_name', 150)->nullable();
            $table->foreignId('recorded_by')->constrained('users')->restrictOnDelete();
            $table->timestamp('recorded_at');
            $table->string('note', 255)->nullable();
            $table->timestamps();

            $table->index(['trip_id', 'recorded_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transport_trip_events');
    }
};
