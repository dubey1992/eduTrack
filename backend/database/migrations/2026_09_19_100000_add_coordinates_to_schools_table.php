<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Where the school actually is.
     *
     * Decimal rather than float: a float cannot hold a coordinate exactly, and
     * "near enough" drifts a school across the road. 10,7 gives roughly a
     * centimetre, which is far more than a school gate needs and leaves room
     * for the transport work that will use it.
     *
     * Nullable, because every existing school was onboarded without one and a
     * made-up coordinate is worse than none.
     */
    public function up(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->decimal('latitude', 10, 7)->nullable()->after('postal_code');
            $table->decimal('longitude', 10, 7)->nullable()->after('latitude');
        });
    }

    public function down(): void
    {
        Schema::table('schools', function (Blueprint $table) {
            $table->dropColumn(['latitude', 'longitude']);
        });
    }
};
