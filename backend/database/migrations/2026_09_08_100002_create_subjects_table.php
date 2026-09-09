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
        Schema::create('subjects', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            // A department can't be deleted while subjects still reference
            // it - the admin must reassign or remove those subjects first.
            $table->foreignId('department_id')->constrained('departments')->restrictOnDelete();
            $table->string('code', 20);
            $table->string('name', 100);
            $table->unsignedTinyInteger('min_class_level');
            $table->unsignedTinyInteger('max_class_level');
            $table->foreignId('lead_teacher_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['school_id', 'code']);
            $table->index('department_id');
            $table->index('lead_teacher_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('subjects');
    }
};
