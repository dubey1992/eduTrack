<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A school's holiday calendar - one row per holiday or break, as an
     * inclusive date range (a single-day holiday has start = end). Ranges
     * within a school never overlap; that is enforced by HolidayService
     * rather than a constraint, since MySQL can't express range exclusion.
     */
    public function up(): void
    {
        Schema::create('holidays', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->string('type', 20);
            $table->date('start_date');
            $table->date('end_date');
            $table->timestamps();

            $table->index(['school_id', 'start_date']);
            $table->index(['school_id', 'end_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('holidays');
    }
};
