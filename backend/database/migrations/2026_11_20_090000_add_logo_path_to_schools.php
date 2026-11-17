<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A school's own uploaded logo (docs/school-logo.md, decided 2026-11-17).
 *
 * Until now a logo was only `logo_url`, a web address the Super Admin typed
 * in. The School Admin now uploads the image; it is decoded, re-encoded and
 * kept in the app's storage under `school-logos/`, and `logo_path` is where.
 * A school's profile is complete once it has one. `logo_url` stays, read
 * only by the PDFs, for the schools that were given an address before.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->string('logo_path', 255)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropColumn('logo_path');
        });
    }
};
