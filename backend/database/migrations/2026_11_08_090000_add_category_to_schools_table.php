<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What kind of account a school is (docs/school-categories.md): demo, trial,
 * live or testing. Separate from `status`, which says whether the school may
 * be used at all.
 *
 * Platform figures count live and trial schools only, and a testing school
 * never sends SMS or WhatsApp. Every school that exists today becomes live,
 * so nothing real drops out of a figure; the Super Admin re-tags the demo
 * and test ones by hand.
 *
 * `trial_ends_on` is set only for a trial. Past it, the Super Admin is
 * warned; the school keeps working (CLAUDE.md rule 4).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->string('category', 20)->default('live')->index();
            $table->date('trial_ends_on')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropIndex(['category']);
            $table->dropColumn(['category', 'trial_ends_on']);
        });
    }
};
