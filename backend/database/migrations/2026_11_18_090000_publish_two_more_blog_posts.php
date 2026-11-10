<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Two more blog posts (asked for 2026-11-10): payroll from the register, and
 * a timetable without clashes. From the Markdown files in
 * database/content/site-pages-2026-11-b, published as they arrive, exactly
 * as the November posts were (2026_11_15_090000_publish_november_blog_posts).
 *
 * Inserted once, here, so a post somebody deletes stays deleted; an address
 * already taken is left alone. `down` removes nothing - by then these are
 * pages somebody may have edited.
 */
return new class extends Migration
{
    public function up(): void
    {
        $now = now();

        foreach (glob(database_path('content/site-pages-2026-11-b/*.md')) as $file) {
            [$meta, $body] = $this->read($file);

            if (DB::table('site_pages')->where('slug', $meta['slug'])->exists()) {
                continue;
            }

            $summary = $meta['summary'] ?? null;
            $author = $meta['author'] ?? 'School365ai Team';

            DB::table('site_pages')->insert([
                'slug' => $meta['slug'],
                'kind' => 'post',
                'title' => $meta['title'],
                'body' => $body,
                'summary' => $summary,
                'author' => $author,
                'published_title' => $meta['title'],
                'published_body' => $body,
                'published_summary' => $summary,
                'published_author' => $author,
                'published_at' => $now,
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

        if ($meta['kind'] !== 'post') {
            throw new RuntimeException("{$file} is not a blog post.");
        }

        return [$meta, trim($parts[2])];
    }
};
