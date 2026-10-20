<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which id a member of staff has on the fingerprint devices
 * (docs/biometric.md, B1).
 *
 * A device reports an id it knows and a time, and nothing else of use. That
 * id is the device's, not ours, so it has to be mapped to somebody - and an
 * unmapped id is a punch nobody can attribute.
 *
 * **One column rather than a table.** A member of staff enrolled on four
 * devices has the same id on all four; that is how the devices are set up,
 * and a row per device would be four copies of one fact.
 *
 * Unique per school, not per platform: two schools number their own staff
 * from 1 and neither is wrong. Nullable, because most staff are not enrolled
 * on a device at all and a blank is not a clash.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('staff_profiles', function (Blueprint $table) {
            $table->string('biometric_user_id', 32)->nullable()->after('employee_id');
            $table->unique(['school_id', 'biometric_user_id']);
        });
    }

    public function down(): void
    {
        Schema::table('staff_profiles', function (Blueprint $table) {
            $table->dropUnique(['school_id', 'biometric_user_id']);
            $table->dropColumn('biometric_user_id');
        });
    }
};
