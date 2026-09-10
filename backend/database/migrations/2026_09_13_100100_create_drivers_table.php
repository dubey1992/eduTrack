<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Drivers are standalone transport records (decided 2026-09-10) - they
     * don't log in, so they are not users or staff profiles.
     */
    public function up(): void
    {
        Schema::create('drivers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 150);
            $table->string('mobile', 20)->nullable();
            $table->string('licence_number', 50);
            $table->date('licence_expiry')->nullable();
            $table->string('status', 20)->default('active');
            $table->timestamps();

            $table->unique(['school_id', 'licence_number']);
            $table->index(['school_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('drivers');
    }
};
