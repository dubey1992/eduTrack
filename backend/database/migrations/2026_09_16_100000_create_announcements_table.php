<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A notice published to a school audience. The audience target and its label
 * are snapshotted so the record still reads correctly after a class is
 * renamed or a department is removed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('announcements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('title', 150);
            $table->text('body');
            $table->string('audience_type', 30);
            $table->unsignedBigInteger('audience_id')->nullable();
            $table->string('audience_label', 120);
            $table->string('channels', 20);
            $table->date('expires_at')->nullable();
            $table->foreignId('published_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('published_at');
            $table->unsignedInteger('recipients_count')->default(0);
            $table->unsignedInteger('sms_count')->default(0);
            $table->unsignedInteger('in_app_count')->default(0);
            $table->softDeletes();
            $table->timestamps();

            $table->index(['school_id', 'published_at']);
            $table->index(['school_id', 'audience_type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('announcements');
    }
};
