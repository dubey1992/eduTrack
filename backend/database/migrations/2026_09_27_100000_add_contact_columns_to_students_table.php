<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where else a student's family can be reached (docs/communication.md).
 *
 * Until now a student carried one contact: the guardian's mobile, which is
 * where the SMS went. Email and WhatsApp as channels need the guardian's
 * address, and an older student can be messaged directly when the school has
 * a number or address for them. All three are optional - a blank means the
 * school has none on record, and a message that needed one is logged as
 * skipped, exactly as a missing mobile is today.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->string('guardian_email', 255)->nullable()->after('guardian_mobile');
            $table->string('student_mobile', 20)->nullable()->after('guardian_email');
            $table->string('student_email', 255)->nullable()->after('student_mobile');
        });
    }

    public function down(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->dropColumn(['guardian_email', 'student_mobile', 'student_email']);
        });
    }
};
