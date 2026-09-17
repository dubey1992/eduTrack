<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Who changed what, and what it was before (CLAUDE.md §13).
 *
 * Built with payroll (Phase 19), its first writer, rather than waiting for
 * Phase 21: retrofitting an audit trail means the months before it have none.
 * Phase 21 extends the same writer to the other modules.
 *
 * Append-only, so there is no updated_at: a row that could be edited would
 * not be a record of anything. Written by the Python backend only; created
 * here because Laravel's migrations own the schema until the cutover (see the
 * queued_jobs migration).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->id();

            // Null for a platform action that belongs to no school.
            $table->foreignId('school_id')->nullable()->constrained()->nullOnDelete();

            // Null for the system itself; kept when the account is later
            // removed, so the history does not lose its rows.
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();

            // `payroll_run.finalized` - the entity and the verb together, so
            // one column answers "what happened".
            $table->string('action', 64);
            $table->string('module', 32);
            $table->string('entity_type', 64);
            $table->unsignedBigInteger('entity_id')->nullable();

            // Before and after. Never a password, token or anything secret.
            $table->json('old_values')->nullable();
            $table->json('new_values')->nullable();

            // IPv6-sized.
            $table->string('ip', 45)->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->index(['school_id', 'created_at']);
            $table->index(['entity_type', 'entity_id']);
            $table->index('user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
