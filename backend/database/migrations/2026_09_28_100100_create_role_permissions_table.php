<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The roles and permissions matrix the Super Admin edits (docs/settings.md).
 *
 * One row per role and module, holding the level - none, view or manage -
 * and only for cells that differ from the defaults built into the
 * application, which reproduce the behaviour every policy had before the
 * matrix existed. Platform-wide: one matrix applies to every school.
 * SUPER_ADMIN is never stored; it is always full.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('role_permissions', function (Blueprint $table) {
            $table->id();
            $table->string('role', 30);
            $table->string('module', 40);
            $table->string('level', 10);
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['role', 'module']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('role_permissions');
    }
};
