<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which member of staff this driver is (docs/driver-app.md, D3).
 *
 * A driver has always been a record - a name, a mobile, a licence and its
 * expiry - with nobody behind it. Now that drivers sign in to the app, the
 * person and the record have to be the same thing: a trip names its driver
 * by `transport_trips.driver_id`, and without this column there is no way
 * to say that the person holding the phone is that driver rather than
 * somebody with a similar name.
 *
 * **Nullable, because a school records a driver long before that driver has
 * a login** - often before they have started. A driver with no staff member
 * simply cannot sign in, which is exactly today's behaviour for every one
 * of them.
 *
 * **Unique**, because one person is one driver. Two driver records pointing
 * at the same employee would make "whose licence expires on Friday" a
 * question with two answers. Nulls do not collide, on either database.
 *
 * `nullOnDelete` rather than cascade: removing somebody from staff must
 * never delete the licence record a trip refers to.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $table->foreignId('staff_profile_id')->nullable()->after('mobile')
                ->unique()->constrained('staff_profiles')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $table->dropConstrainedForeignId('staff_profile_id');
        });
    }
};
