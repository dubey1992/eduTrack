<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Platform messaging, M1 (docs/platform-messaging.md, decided 2026-10-29).
 *
 * School365ai sends every school's SMS and WhatsApp through its own Twilio
 * account and a shared sender, and charges schools for it, so the account
 * and the WhatsApp templates belong to the platform rather than to each
 * school.
 *
 * - platform_messaging: one row. The provider ("log", the Demo Gateway that
 *   sends nothing, or "twilio") and its account, encrypted as JSON
 *   (account SID, auth token, SMS sender, WhatsApp sender) by
 *   school/crypto.py, never returned by the API.
 * - platform_whatsapp_templates: one row per event that has an approved
 *   WhatsApp template - the Twilio Content SID, its language, and which of
 *   the event's tokens fill its numbered parameters.
 *
 * The per-school columns this replaces (communication_settings.provider,
 * whatsapp_provider, sender_id, credentials, and whatsapp_templates) are
 * left in place and simply no longer read, so nothing a school saved is
 * destroyed by this change.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('platform_messaging', function (Blueprint $table) {
            $table->id();
            $table->string('provider', 50)->default('log');
            $table->text('credentials')->nullable();
            $table->timestamp('last_tested_at')->nullable();
            $table->string('last_test_error', 255)->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('platform_whatsapp_templates', function (Blueprint $table) {
            $table->id();
            $table->string('event', 50)->unique();
            $table->string('template_name', 120);
            $table->string('language', 10)->default('en');
            $table->string('parameters', 255)->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('platform_whatsapp_templates');
        Schema::dropIfExists('platform_messaging');
    }
};
