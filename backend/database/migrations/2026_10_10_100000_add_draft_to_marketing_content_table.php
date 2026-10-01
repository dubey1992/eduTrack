<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Editing the homepage without publishing it (docs/marketing-content.md).
 *
 * `document` is what the world sees; `draft` is what the Super Admin is
 * working on. They are separate columns rather than one with a flag because
 * the whole point is that both exist at once: somebody rewrites the hero
 * over a morning while visitors keep reading the version that was signed
 * off.
 *
 * `published_at` and `published_by` answer "who changed the front page, and
 * when" - the first question anybody asks when the wording surprises them.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('marketing_content', function (Blueprint $table) {
            $table->json('draft')->nullable()->after('document');
            $table->timestamp('published_at')->nullable()->after('draft');
            $table->foreignId('published_by')->nullable()->after('published_at')
                ->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('marketing_content', function (Blueprint $table) {
            $table->dropForeign(['published_by']);
            $table->dropColumn(['draft', 'published_at', 'published_by']);
        });
    }
};
