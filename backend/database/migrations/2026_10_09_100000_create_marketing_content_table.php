<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The words on the public homepage (docs/marketing-content.md).
 *
 * One row, like `mail_settings`: this is the platform's own page, not a
 * school's, so there is nothing to scope it by and no `school_id`.
 *
 * `document` holds only what somebody has *changed*. The page's own copy
 * lives in the client as its defaults, which is what lets the homepage
 * render correctly when this table is empty, when the request fails, and
 * before the first byte of it arrives. Storing the whole page here instead
 * would mean a marketing site that goes blank when an API call does.
 *
 * No `draft` column yet: editing and publishing are the next slice, and a
 * column nothing writes is a column nobody can explain.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('marketing_content', function (Blueprint $table) {
            $table->id();
            $table->json('document')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('marketing_content');
    }
};
