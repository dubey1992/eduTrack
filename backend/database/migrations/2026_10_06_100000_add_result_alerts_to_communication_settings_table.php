<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Whether a school tells guardians when a result is published
 * (docs/assessments.md).
 *
 * The fourth alert switch, beside attendance, transport and leave, because it
 * is the same kind of decision: a school that hands out printed report cards
 * does not want a text as well, and switching the whole Communication module
 * off to stop one alert is too blunt.
 *
 * On by default, like the transport and leave switches: a school that has
 * turned messaging on has said it wants to reach guardians, and a published
 * result is the news guardians most expect to receive.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('communication_settings', function (Blueprint $table) {
            $table->boolean('result_alerts_enabled')->default(true)->after('leave_alerts_enabled');
        });
    }

    public function down(): void
    {
        Schema::table('communication_settings', function (Blueprint $table) {
            $table->dropColumn('result_alerts_enabled');
        });
    }
};
