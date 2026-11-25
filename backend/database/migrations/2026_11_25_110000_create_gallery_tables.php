<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Events and photos for the Family app (docs/mobile-apps-review.md, M12,
 * 8.6, decided 2026-11-25).
 *
 * An admin posts an event for the whole school (class_section_id null) or a
 * class; a class teacher posts to their own class. Up to 20 photos each,
 * re-encoded to at most 1600 px, with a 400 px copy for the grid
 * (thumb_path). Parents see the school's events and their children's
 * classes'; every file is read only through a signed-in endpoint.
 *
 * Children are not tagged in photos: that waits for a photo-consent field
 * on students.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gallery_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('class_section_id')->nullable()->constrained();
            $table->string('title', 120);
            $table->date('event_date');
            $table->string('description', 500)->nullable();
            $table->foreignId('posted_by')->nullable()->constrained('users');
            $table->timestamps();

            $table->index(['school_id', 'event_date']);
            $table->index('class_section_id');
        });

        Schema::create('gallery_photos', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained();
            $table->foreignId('gallery_event_id')->constrained()->cascadeOnDelete();
            $table->string('file_path', 255);
            $table->string('thumb_path', 255);
            $table->foreignId('uploaded_by')->nullable()->constrained('users');
            $table->timestamps();

            $table->index('gallery_event_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gallery_photos');
        Schema::dropIfExists('gallery_events');
    }
};
