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
        Schema::create('students', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            // Nullable so a student can exist between class assignments, but
            // SchoolClassService::deleteSection() refuses to delete a
            // section that still has students - this is a safety net, not
            // the normal path.
            $table->foreignId('class_section_id')->nullable()->constrained('class_sections')->nullOnDelete();
            $table->string('admission_number', 30);
            $table->string('first_name', 100);
            $table->string('last_name', 100);
            $table->string('roll_number', 20)->nullable();
            $table->string('guardian_name', 150);
            $table->string('guardian_mobile', 20)->nullable();
            $table->text('address')->nullable();
            $table->string('status')->default('active');
            $table->timestamps();

            $table->unique(['school_id', 'admission_number']);
            $table->index('class_section_id');
            $table->index('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('students');
    }
};
