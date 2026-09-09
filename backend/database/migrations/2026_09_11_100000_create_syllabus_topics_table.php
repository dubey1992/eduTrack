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
        Schema::create('syllabus_topics', function (Blueprint $table) {
            $table->id();
            // Snapshotted directly rather than derived through subject_id
            // every query, same reasoning as TimetableEntry::school_id.
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('subject_id')->constrained()->cascadeOnDelete();
            $table->string('title', 255);
            $table->unsignedInteger('sequence_number');
            $table->timestamps();

            // Defines the curriculum order for the subject - two topics
            // can't share a position.
            $table->unique(['subject_id', 'sequence_number']);
            $table->index('school_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('syllabus_topics');
    }
};
