<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An announcement can now go out on any mix of in-app, SMS, WhatsApp and
 * email. The column keeps its three original values ("sms_in_app", "sms",
 * "in_app") and also holds a comma-separated list such as
 * "in_app,sms,whatsapp,email", which is longer than the 20 characters it was
 * created with.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('announcements', function (Blueprint $table) {
            $table->string('channels', 60)->change();
        });
    }

    public function down(): void
    {
        Schema::table('announcements', function (Blueprint $table) {
            $table->string('channels', 20)->change();
        });
    }
};
