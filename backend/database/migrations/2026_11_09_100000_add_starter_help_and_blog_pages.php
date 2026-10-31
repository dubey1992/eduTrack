<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The help centre's first articles and the blog's first drafts
 * (docs/seo.md, S5), from the Markdown files in database/content/site-pages.
 *
 * Each file starts with a few `key: value` lines between `---` lines - kind,
 * slug, title, summary, and a topic (help) or an author (post) - and the rest
 * is the page text in the Website Pages format.
 *
 * Help articles go live at once. Blog posts arrive as unpublished drafts for
 * the Super Admin to read, edit and publish: they carry the company's voice.
 *
 * Inserted once, here, rather than by a command run at every deploy: a
 * migration runs once per database, so a draft somebody deletes stays
 * deleted. An address already taken is left alone.
 *
 * `down` removes nothing: by then these are pages somebody may have edited,
 * and rolling back a schema should never delete what people wrote.
 */
return new class extends Migration
{
    public function up(): void
    {
        $now = now();

        foreach (glob(database_path('content/site-pages/*.md')) as $file) {
            [$meta, $body] = $this->read($file);

            if (DB::table('site_pages')->where('slug', $meta['slug'])->exists()) {
                continue;
            }

            $live = $meta['kind'] === 'help';
            $summary = $meta['summary'] ?? null;
            $author = $meta['kind'] === 'post' ? ($meta['author'] ?? 'School365ai Team') : null;
            $topic = $meta['kind'] === 'help' ? ($meta['topic'] ?? null) : null;

            DB::table('site_pages')->insert([
                'slug' => $meta['slug'],
                'kind' => $meta['kind'],
                'title' => $meta['title'],
                'body' => $body,
                'summary' => $summary,
                'author' => $author,
                'topic' => $topic,
                'published_title' => $live ? $meta['title'] : null,
                'published_body' => $live ? $body : null,
                'published_summary' => $live ? $summary : null,
                'published_author' => $live ? $author : null,
                'published_topic' => $live ? $topic : null,
                'published_at' => $live ? $now : null,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    public function down(): void
    {
        // Nothing: see the note above.
    }

    /** @return array{0: array<string, string>, 1: string} */
    private function read(string $file): array
    {
        $text = str_replace("\r\n", "\n", file_get_contents($file));

        if (! preg_match('/\A---\n(.*?)\n---\n(.*)\z/s', $text, $parts)) {
            throw new RuntimeException("No front matter in {$file}.");
        }

        $meta = [];
        foreach (explode("\n", $parts[1]) as $line) {
            if (str_contains($line, ':')) {
                [$key, $value] = explode(':', $line, 2);
                $meta[trim($key)] = trim($value);
            }
        }

        foreach (['kind', 'slug', 'title'] as $required) {
            if (empty($meta[$required])) {
                throw new RuntimeException("{$file} has no {$required}.");
            }
        }

        return [$meta, trim($parts[2])];
    }
};
