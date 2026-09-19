<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The SMTP server the platform sends through, set by the Super Admin in the
 * app rather than in a file on the server (docs/communication.md).
 *
 * One row for the whole platform: password resets, receipts, payslips and
 * the email channel all leave through it. When the row is missing or
 * switched off, the MAIL_* environment variables apply instead, so a fresh
 * deployment still sends. The password is encrypted by the application before
 * it is written and is never returned by the API.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mail_settings', function (Blueprint $table) {
            $table->id();
            $table->boolean('is_active')->default(true);
            $table->string('host', 255);
            $table->unsignedSmallInteger('port')->default(587);
            // none, tls (STARTTLS) or ssl.
            $table->string('encryption', 10)->default('tls');
            $table->string('username', 255)->nullable();
            $table->text('password')->nullable();
            $table->string('from_address', 255);
            $table->string('from_name', 120);
            $table->timestamp('last_tested_at')->nullable();
            $table->string('last_test_error', 255)->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mail_settings');
    }
};
