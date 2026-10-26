<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The phones a person is signed in on, for push notifications
 * (docs/teacher-app.md, T6).
 *
 * **One row per phone, not per person.** A teacher with a phone and a tablet
 * has two rows, and both buzz.
 *
 * **The token is unique across everybody.** Firebase gives a token to an
 * install of the app, not to a person. When a shared staff-room phone signs
 * in as somebody else, the row moves to them rather than a second row
 * telling the first person the second person's news.
 *
 * Removed at sign-out, and by the sender when Firebase says a token is no
 * longer registered (the app was uninstalled). `last_seen_at` is refreshed
 * each time the app registers, so a later clean-up can drop phones nobody
 * has opened in months.
 *
 * No `school_id`: a token belongs to a person, and the person's school is
 * theirs already. Every push is sent to the user an in-app message was
 * written for, never chosen by school.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_tokens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            // FCM registration tokens run to about 160 characters today;
            // 255 leaves room without being a TEXT column that cannot be
            // uniquely indexed everywhere.
            $table->string('token', 255)->unique();
            $table->string('platform', 16);
            // Which of the apps: the staff app or the driver app.
            $table->string('app', 20);
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();

            $table->index('user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
