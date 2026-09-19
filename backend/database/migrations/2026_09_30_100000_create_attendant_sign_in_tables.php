<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How a Bus Attendant signs in (docs/maps.md, "The Bus Attendant").
 *
 * An attendant signs in with a mobile number and a 4-digit passcode - but
 * only on a phone the school registered. Four digits alone are ten thousand
 * guesses; tied to a registered device, a passcode is useless without the
 * phone it was set on.
 *
 * attendant_credentials - one row per attendant account: the mobile number
 * they sign in with (digits only, unique), the passcode hash, the wrong-guess
 * count and the lock, and the current one-time setup code (hashed) with its
 * expiry.
 *
 * attendant_devices - the phones (or browsers) registered to an attendant.
 * Only a SHA-256 of each device's secret is stored; the secret itself lives
 * on the device and is shown to nobody.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendant_credentials', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            // "+919876543210" - the number as dialled, no spaces.
            $table->string('login_mobile', 20)->unique();
            $table->string('passcode', 255)->nullable();
            $table->unsignedSmallInteger('failed_attempts')->default(0);
            // Locked until an administrator unlocks it; there is no timeout.
            $table->timestamp('locked_at')->nullable();
            $table->string('setup_code', 255)->nullable();
            $table->timestamp('setup_code_expires_at')->nullable();
            $table->foreignId('setup_code_issued_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('attendant_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('secret', 64)->unique();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'revoked_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendant_devices');
        Schema::dropIfExists('attendant_credentials');
    }
};
