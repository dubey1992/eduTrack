<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A school asking to be shown the product (decided 2026-10-29).
 *
 * Kept apart from early_access_requests on purpose: somebody joining early
 * access wants an account, somebody asking for a demo wants half an hour of
 * a person's time on a particular day. They are followed up differently, by
 * a different list. Like early access it belongs to no tenant - it exists
 * before any school does.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('demo_requests', function (Blueprint $table) {
            $table->id();

            // Who is asking.
            $table->string('contact_name', 150);
            $table->string('school_name', 150);
            $table->string('email');
            $table->string('phone', 20);
            $table->string('city', 100)->nullable();
            $table->string('country', 100);
            $table->unsignedInteger('expected_students')->nullable();

            // When they would like it. The time is a part of the day rather
            // than a clock time, in the visitor's own timezone - which is
            // kept, since "morning" in Lagos is not morning in Delhi.
            $table->date('preferred_date');
            $table->string('preferred_time', 20)->nullable();
            $table->string('timezone', 64)->nullable();
            $table->text('message')->nullable();

            // What we have done about it: new, scheduled, done, declined.
            $table->string('status', 20)->default('new');
            $table->text('notes')->nullable();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();

            $table->timestamps();

            // The panel lists newest first and filters by status.
            $table->index(['status', 'created_at']);
            // A second submission from the same address finds the open one.
            $table->index('email');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('demo_requests');
    }
};
