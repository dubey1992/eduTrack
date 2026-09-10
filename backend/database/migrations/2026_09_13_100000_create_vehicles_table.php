<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vehicles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 50);
            $table->string('registration_number', 30);
            $table->unsignedSmallInteger('capacity');
            $table->string('status', 20)->default('active');
            $table->timestamps();

            $table->unique(['school_id', 'registration_number']);
            $table->index(['school_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vehicles');
    }
};
