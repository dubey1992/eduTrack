<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Photos on a daily teaching report (docs/mobile-apps-review.md, M9, 6.6,
 * decided 2026-11-24): up to three per report - the board, the children's
 * work - taken with the Staff app's camera.
 *
 * Staff only: the report's teacher, their HOD and the school's admins see
 * them; parents never do. The author adds or removes them until the report
 * is reviewed. Each is decoded and re-encoded on upload, like a profile
 * photo. Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('teaching_report_photos', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->foreignId('daily_teaching_report_id')->constrained()->cascadeOnDelete();
            $table->string('file_path', 255);
            $table->timestamps();

            $table->index('daily_teaching_report_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('teaching_report_photos');
    }
};
