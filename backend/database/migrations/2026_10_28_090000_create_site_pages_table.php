<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The public website's own pages - About Us, Privacy Policy, Terms of Use,
 * and whatever else the Super Admin adds (docs/site-pages.md).
 *
 * Platform-owned like `marketing_content`: these pages belong to the
 * product, not to a school, so there is no `school_id`.
 *
 * Draft and published versions sit side by side in one row, for the same
 * reason as the homepage: somebody rewrites the privacy policy over a
 * morning while visitors keep reading the version that was signed off.
 * `title`/`body` are the draft; `published_title`/`published_body` are what
 * the world sees, and are null until the page is first published.
 *
 * The three built-in pages need no row to exist. Their text ships in code
 * (school/site_pages.py) and a row appears the first time somebody saves or
 * publishes one, so an empty table still serves a privacy policy.
 *
 * `body` has no database default: MySQL refuses one on a text column, and
 * the application always writes it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('site_pages', function (Blueprint $table) {
            $table->id();
            // The page's address: school365ai.com/<slug>.
            $table->string('slug', 60)->unique();
            $table->string('title', 120);
            $table->longText('body');
            $table->string('published_title', 120)->nullable();
            $table->longText('published_body')->nullable();
            $table->timestamp('published_at')->nullable();
            $table->foreignId('published_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('site_pages');
    }
};
