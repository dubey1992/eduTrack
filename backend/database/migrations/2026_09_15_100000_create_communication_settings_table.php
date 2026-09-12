<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One row per school: which alerts go out and through which gateway.
 * A school with no row falls back to the defaults in config/communication.php.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('communication_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->unique()->constrained()->cascadeOnDelete();
            $table->boolean('sms_enabled')->default(true);
            $table->string('attendance_alerts', 20)->default('absent');
            $table->boolean('transport_alerts_enabled')->default(true);
            $table->boolean('leave_alerts_enabled')->default(true);
            $table->string('provider', 50)->default('log');
            $table->string('sender_id', 20)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('communication_settings');
    }
};
