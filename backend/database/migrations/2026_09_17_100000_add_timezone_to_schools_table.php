<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Schools run in different countries, so "today" is a property of the
     * school, not of the server. Existing rows default to UTC, which is what
     * the application assumed before this column existed - so adding it
     * changes no stored data and no behaviour until a school is given its
     * real zone.
     */
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->string('timezone', 64)->default('UTC')->after('currency_code');
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropColumn('timezone');
        });
    }
};
