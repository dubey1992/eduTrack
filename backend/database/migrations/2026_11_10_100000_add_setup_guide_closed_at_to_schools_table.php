<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * When a school's setup guide was finished or hidden (docs/onboarding.md, O4).
 *
 * Remembered for the whole school, not per person: once one School Admin
 * closes it, another does not find it open again. Null means the guide still
 * shows on the dashboard; reopening it clears this.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->timestamp('setup_guide_closed_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropColumn('setup_guide_closed_at');
        });
    }
};
