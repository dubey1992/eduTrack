<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which modules a school has switched on, and each module's own settings
 * (docs/settings.md).
 *
 * One row per school and module, and only once somebody has touched it: a
 * school with no row has every module on with its default settings, so
 * nothing changes for existing schools. Two switches on purpose - the
 * platform grants a module to a school (Super Admin), and the school may
 * still switch it off for itself (School Admin); a module is on only when
 * both say so. `settings` holds the module's own options as JSON, checked
 * against the module's schema by the application.
 *
 * Written by the Python backend only; created here because Laravel's
 * migrations own the schema until the cutover.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('module_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('module', 40);
            $table->boolean('platform_enabled')->default(true);
            $table->boolean('school_enabled')->default(true);
            $table->json('settings')->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['school_id', 'module']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('module_settings');
    }
};
