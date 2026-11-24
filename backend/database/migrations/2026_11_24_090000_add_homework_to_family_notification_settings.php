<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The Family app's homework switch (docs/mobile-apps-review.md, M8, 8.1):
 * whether a parent gets the evening "homework for today" message. On, like
 * every other switch, until the parent turns it off; every existing row
 * starts on.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('family_notification_settings', function (Blueprint $table) {
            $table->boolean('homework')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('family_notification_settings', function (Blueprint $table) {
            $table->dropColumn('homework');
        });
    }
};
