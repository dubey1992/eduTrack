<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which kinds of message a parent wants on the Family app
 * (docs/parent-student-app.md, F1, "Notifications with per-type switches").
 *
 * One row per family account, made the first time they change a switch;
 * no row means every kind on. Each switch decides whether the app gets its
 * copy of that kind of message - the school's own SMS and WhatsApp are the
 * school's settings, never these. An emergency message has no switch: it
 * always arrives.
 *
 * - attendance: absent, on leave, late register
 * - transport:  boarded, dropped, not on the bus
 * - fee:        fee reminders and receipts
 * - result:     published test results
 * - notices:    announcements and the school's general messages
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('family_notification_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->boolean('attendance')->default(true);
            $table->boolean('transport')->default(true);
            $table->boolean('fee')->default(true);
            $table->boolean('result')->default(true);
            $table->boolean('notices')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('family_notification_settings');
    }
};
