<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links a fanned-out copy back to the announcement it came from, and gives a
 * message an optional subject line (an announcement's title) for the inbox.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->foreignId('announcement_id')->nullable()->after('event')->constrained()->nullOnDelete();
            $table->string('subject', 150)->nullable()->after('student_name');
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->dropConstrainedForeignId('announcement_id');
            $table->dropColumn('subject');
        });
    }
};
