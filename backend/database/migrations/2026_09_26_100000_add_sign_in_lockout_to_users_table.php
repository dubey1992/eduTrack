<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Account lockout (Phase 21, docs/security.md).
 *
 * Ten wrong passwords in a row lock the account for fifteen minutes. The
 * counter lives on the user rather than in a cache so the lock survives a
 * restart and holds across every server process - a guesser who waits for a
 * deploy should not get a fresh ten tries.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover (see the queued_jobs migration).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Wrong passwords since the last successful sign-in.
            $table->unsignedSmallInteger('failed_login_attempts')->default(0)->after('must_change_password');

            // Sign-in is refused until this instant; null when not locked.
            $table->timestamp('locked_until')->nullable()->after('failed_login_attempts');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['failed_login_attempts', 'locked_until']);
        });
    }
};
