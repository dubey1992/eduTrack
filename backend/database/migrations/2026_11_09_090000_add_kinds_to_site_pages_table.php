<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Website Pages become three kinds (docs/seo.md, S5): a page, a blog post
 * (/blog/<slug>) or a help article (/help/<slug>).
 *
 * Each new detail has a draft and a published copy, like the title and
 * body: editing a live post's summary or cover changes nothing visitors see
 * until it is published.
 *
 * - `kind`: page, post or help. Set when the page is created.
 * - `summary`: the line under the title in the blog and help lists, and the
 *   search snippet. Required for posts and help articles.
 * - `author`: a post's byline - a typed name, "School365ai Team" by default.
 * - `topic`: a help article's section of the help centre (a key from
 *   school/site_pages.py HELP_TOPICS).
 * - `cover_path`: a post's cover image in the private media storage, checked
 *   and re-encoded on upload; the published one is copied into the public
 *   site when the post is written out.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('site_pages', function (Blueprint $table) {
            $table->string('kind', 10)->default('page')->index();
            $table->string('summary', 300)->nullable();
            $table->string('published_summary', 300)->nullable();
            $table->string('author', 100)->nullable();
            $table->string('published_author', 100)->nullable();
            $table->string('topic', 40)->nullable();
            $table->string('published_topic', 40)->nullable();
            $table->string('cover_path', 255)->nullable();
            $table->string('published_cover_path', 255)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('site_pages', function (Blueprint $table) {
            $table->dropIndex(['kind']);
            $table->dropColumn([
                'kind', 'summary', 'published_summary', 'author', 'published_author',
                'topic', 'published_topic', 'cover_path', 'published_cover_path',
            ]);
        });
    }
};
