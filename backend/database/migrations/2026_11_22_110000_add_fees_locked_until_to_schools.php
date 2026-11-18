<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The fee books' date lock (docs/dashboard.md, D3, decided 2026-11-18).
 *
 * One "locked up to" date per school: no receipt, cancellation, discount,
 * waiver, late fine or refund dated on or before it can be recorded. Null is
 * nothing locked. Set and moved by a School Admin or an Accountant; moving it
 * back needs a reason, and every change is in the audit log - which is the
 * lock's history, so it needs no table of its own.
 *
 * Written by the Python backend only.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->date('fees_locked_until')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropColumn('fees_locked_until');
        });
    }
};
