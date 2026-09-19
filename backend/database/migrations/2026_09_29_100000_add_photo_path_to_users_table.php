<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A profile photo for every account (docs/profile.md).
 *
 * The column holds the stored file's path inside the application's storage,
 * never a public URL: the photo is served through an authenticated endpoint,
 * so a guessed or leaked path is not a way to see somebody's face. Null means
 * no photo, and the app shows initials instead.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('photo_path', 255)->nullable()->after('mobile');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('photo_path');
        });
    }
};
