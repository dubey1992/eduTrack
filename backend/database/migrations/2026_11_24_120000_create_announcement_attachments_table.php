<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Files carried by a notice (docs/mobile-apps-review.md, M9, 8.3, decided
 * 2026-11-24): up to three per announcement, PDF, JPEG or PNG, 5 MB each.
 *
 * A file is uploaded on its own before the notice is published - one file
 * per request, which the shared host copes with - and is "pending"
 * (`announcement_id` null) until the publish names it. Pending files are
 * the uploader's only, and are cleared after a day if never published.
 *
 * Read only through the authenticated endpoint, by the notice's publishers
 * and its in-app recipients. Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('announcement_attachments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('announcement_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('uploaded_by')->constrained('users')->restrictOnDelete();
            $table->string('file_path', 255);
            $table->string('original_name', 150);
            $table->string('content_type', 50);
            $table->unsignedInteger('size_bytes');
            $table->unsignedTinyInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index('announcement_id');
            // Clearing a person's unpublished uploads.
            $table->index(['uploaded_by', 'announcement_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('announcement_attachments');
    }
};
