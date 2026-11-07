<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How a parent signs in to the Family app (docs/parent-student-app.md, F0,
 * decision D1).
 *
 * The same shape as the bus crew's sign-in: the school office issues a
 * one-time setup code, printed on a letter for the parent; on the parent's
 * phone, mobile + setup code + a new 6-digit passcode registers the phone;
 * from then on mobile + passcode signs in, on that phone only.
 *
 * family_credentials - one row per family account: the mobile they sign in
 * with, the passcode hash, wrong guesses and the time of the lock (it lifts
 * after 15 minutes), and the current setup code (hashed) with its expiry. A
 * parent with children in two schools has two accounts, so the mobile is
 * unique within a school, not across schools.
 *
 * family_devices - the phones registered to a family account. Only a SHA-256
 * of each device's secret is stored; the secret lives on the phone.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('family_credentials', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('login_mobile', 20);
            $table->string('passcode', 255)->nullable();
            $table->unsignedSmallInteger('failed_attempts')->default(0);
            $table->timestamp('locked_at')->nullable();
            $table->string('setup_code', 255)->nullable();
            $table->timestamp('setup_code_expires_at')->nullable();
            $table->foreignId('setup_code_issued_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['school_id', 'login_mobile']);
            $table->index('login_mobile');
        });

        Schema::create('family_devices', function (Blueprint $table) {
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
        Schema::dropIfExists('family_devices');
        Schema::dropIfExists('family_credentials');
    }
};
