<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What the phone network reported back about a message (docs/dashboard.md,
 * D2, decided 2026-11-18).
 *
 * `status` stays what it always was - queued, sent, failed, skipped: what
 * School365ai did with the message. These columns are what happened after
 * the provider took it, as Twilio's status callback reports it:
 *
 * - `delivery_status` - delivered, read (WhatsApp) or undelivered; null until
 *   a report arrives, and for every message sent before this existed.
 * - `delivered_at` - when the delivered (or read) report came in.
 * - `delivery_error` - the provider's reason a message did not arrive.
 *
 * `provider_message_id` is indexed because every report finds its message by
 * it.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->string('delivery_status', 20)->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->string('delivery_error', 255)->nullable();
            $table->index('provider_message_id');
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->dropIndex(['provider_message_id']);
            $table->dropColumn(['delivery_status', 'delivered_at', 'delivery_error']);
        });
    }
};
