<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * WhatsApp and email as channels, and the school's own provider accounts
 * (docs/communication.md).
 *
 * Each school signs its own contract with a provider - a school in Lagos and
 * one in Pune do not share a Twilio account - so the credentials live on the
 * school's settings row rather than in the server's environment. The column
 * holds a JSON object keyed by provider, encrypted by the application before
 * it is written; the database never sees a key in clear, and the API never
 * returns one.
 *
 * Both new channels are off until a school turns them on, so nothing changes
 * for a school that has not opened the settings screen.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('communication_settings', function (Blueprint $table) {
            $table->boolean('whatsapp_enabled')->default(false)->after('leave_alerts_enabled');
            $table->string('whatsapp_provider', 50)->default('log')->after('whatsapp_enabled');
            $table->boolean('email_enabled')->default(false)->after('whatsapp_provider');
            $table->text('credentials')->nullable()->after('sender_id');
        });
    }

    public function down(): void
    {
        Schema::table('communication_settings', function (Blueprint $table) {
            $table->dropColumn(['whatsapp_enabled', 'whatsapp_provider', 'email_enabled', 'credentials']);
        });
    }
};
