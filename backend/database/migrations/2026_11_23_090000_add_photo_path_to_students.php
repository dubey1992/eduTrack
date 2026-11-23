<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A student's photo (docs/student-photos.md, P1, decided 2026-11-23).
 *
 * A storage path under `student-photos/`, never a URL: the image is read
 * back only through the authenticated `GET /students/{id}/photo`. Null means
 * no photo, which is every student already on the roll. Only the current
 * photo is kept - a new one replaces the file. Not indexed: it is read with
 * the student, never searched by.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->string('photo_path', 255)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->dropColumn('photo_path');
        });
    }
};
