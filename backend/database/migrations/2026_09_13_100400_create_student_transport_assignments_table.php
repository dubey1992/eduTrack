<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One route + one stop per student, used for both pickup and drop
     * (decided 2026-09-10). Deleting a route/stop that still has students
     * is refused by the service, so the FKs restrict rather than cascade.
     */
    public function up(): void
    {
        Schema::create('student_transport_assignments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('route_id')->constrained('transport_routes')->restrictOnDelete();
            $table->foreignId('transport_stop_id')->constrained('transport_stops')->restrictOnDelete();
            $table->timestamps();

            $table->unique('student_id');
            $table->index('route_id');
            $table->index('transport_stop_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('student_transport_assignments');
    }
};
