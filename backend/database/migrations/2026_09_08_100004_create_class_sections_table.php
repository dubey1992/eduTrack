<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('class_sections', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_class_id')->constrained('school_classes')->cascadeOnDelete();
            $table->string('name', 10);
            $table->string('room_number', 20)->nullable();
            $table->foreignId('class_teacher_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['school_class_id', 'name']);
            $table->index('class_teacher_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('class_sections');
    }
};
