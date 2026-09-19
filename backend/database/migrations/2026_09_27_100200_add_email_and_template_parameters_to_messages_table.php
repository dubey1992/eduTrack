<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An email copy of a message needs the address it went to, snapshotted like
 * the mobile number so the log stays readable after the record changes.
 *
 * A WhatsApp copy is not sent as free text: the provider only accepts a
 * template the school registered, filled with ordered parameters. Those
 * values are fixed when the message is recorded and kept here, so the worker
 * that sends it later does not have to rebuild them from data that may have
 * changed since.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->string('recipient_email', 255)->nullable()->after('recipient_mobile');
            $table->json('template_parameters')->nullable()->after('body');
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->dropColumn(['recipient_email', 'template_parameters']);
        });
    }
};
