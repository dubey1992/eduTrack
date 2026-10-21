<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A shared secret a device sends with its punches (docs/biometric.md, B4).
 *
 * The push endpoint cannot be authenticated the way everything else is: a
 * fingerprint reader has no account, no token, and no way to be given one.
 * All it can say is its serial number, and a serial is not a credential -
 * it is printed on the box and sent in the clear.
 *
 * Where the firmware allows an extra query parameter, this is what goes in
 * it. Nullable on purpose, and null means no secret is required: older
 * boxes cannot send one at all, and refusing their punches would leave the
 * school worse off than the CSV upload it already has.
 *
 * Not a password, so not hashed: the device has to send it verbatim and we
 * have to compare it verbatim. It limits damage rather than preventing it,
 * which is why the punches it guards can only ever write a time - never a
 * status, never a day's presence, and never anything payroll reads direct.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('biometric_devices', function (Blueprint $table) {
            $table->string('push_key', 64)->nullable()->after('serial_number');
        });
    }

    public function down(): void
    {
        Schema::table('biometric_devices', function (Blueprint $table) {
            $table->dropColumn('push_key');
        });
    }
};
