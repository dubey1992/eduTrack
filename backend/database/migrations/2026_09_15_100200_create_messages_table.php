<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Every message the product sends, whatever the channel. Recipient details
 * are snapshotted so the log stays readable after a student or staff record
 * changes, and the row is kept even when a send is skipped so admins can see
 * what would have gone out.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('event', 50);
            $table->string('category', 30);
            $table->string('channel', 20);
            $table->string('recipient_name', 150);
            $table->string('recipient_mobile', 20)->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('student_id')->nullable()->constrained()->nullOnDelete();
            $table->string('student_name', 150)->nullable();
            $table->text('body');
            $table->string('status', 20);
            $table->string('provider', 50)->nullable();
            $table->string('provider_message_id', 100)->nullable();
            $table->string('failure_reason', 255)->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('read_at')->nullable();
            $table->timestamps();

            $table->index(['school_id', 'created_at']);
            $table->index(['school_id', 'category']);
            $table->index(['school_id', 'status']);
            $table->index(['user_id', 'read_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('messages');
    }
};
