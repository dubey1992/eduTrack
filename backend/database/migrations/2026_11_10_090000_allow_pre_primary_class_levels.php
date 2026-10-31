<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Pre-primary years below 0 (docs/onboarding.md): Playgroup -3, Nursery -2,
 * LKG -1, UKG 0, then Class 1 to 12. Schools that already use 0 for the year
 * before Class 1 keep their order. A subject's class range follows.
 *
 * Going back fails while a class or subject sits below 0, on purpose: those
 * rows would otherwise be clipped to 0 and lose their order.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('school_classes', function (Blueprint $table) {
            $table->tinyInteger('level')->change();
        });

        Schema::table('subjects', function (Blueprint $table) {
            $table->tinyInteger('min_class_level')->change();
            $table->tinyInteger('max_class_level')->change();
        });
    }

    public function down(): void
    {
        Schema::table('school_classes', function (Blueprint $table) {
            $table->unsignedTinyInteger('level')->change();
        });

        Schema::table('subjects', function (Blueprint $table) {
            $table->unsignedTinyInteger('min_class_level')->change();
            $table->unsignedTinyInteger('max_class_level')->change();
        });
    }
};
