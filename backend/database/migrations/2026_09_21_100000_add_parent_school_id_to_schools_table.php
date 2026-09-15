<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A school group: several branches under one parent.
 *
 * A branch IS a school - it has its own address, currency, timezone, academic
 * years, staff and roll - so this is the whole schema change. Every table
 * carrying school_id already points at the branch that owns the record, and
 * none of them move.
 *
 * Null for a standalone school, which is what every existing row is.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->foreignId('parent_school_id')
                ->nullable()
                ->after('id')
                ->constrained('schools')
                // Deleting a parent leaves its branches standing as
                // independent schools. Cascading would delete a whole group's
                // students because somebody removed the head office row.
                ->nullOnDelete();

            $table->index('parent_school_id');
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropConstrainedForeignId('parent_school_id');
        });
    }
};
