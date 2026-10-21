<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Every punch a device recorded (docs/biometric.md, B2).
 *
 * Kept raw rather than folded straight into the staff register, for three
 * reasons: an admin asking why check-in says 09:02 needs to see the punch an
 * unmapped device id needs somewhere to sit until somebody fixes the
 * enrolment, and knowing what has already been seen is what makes a re-upload
 * safe.
 *
 * **`staff_profile_id` is nullable, and that is the point.** A device reports
 * an id it knows; if nobody has mapped that id to a person, the punch is
 * still recorded and still visible. Dropping it would mean the first anybody
 * knew of a missing enrolment was a register with nothing in it.
 *
 * **The uniqueness deliberately ignores source and device.** The same person
 * at the same instant is the same punch however it reached us - a school that
 * uploads a CSV covering days a device already pushed must not end up with
 * two of everything, and that is the common case rather than the exotic one.
 * Second resolution makes a genuine coincidence (one person, two readers, the
 * same second) vanishingly unlikely, and a duplicate far more likely.
 *
 * `punched_at` is a UTC instant; `local_date` is the school's own day, worked
 * out with its timezone (docs/timezones.md). Both, because the register is
 * kept per local day and the instant is what orders punches within it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('biometric_punches', function (Blueprint $table) {
            $table->id();
            $table->foreignId('school_id')->constrained()->cascadeOnDelete();
            // Null for an uploaded file: the export names the person and the
            // time, not which reader they used.
            $table->foreignId('device_id')->nullable()->constrained('biometric_devices')->nullOnDelete();
            $table->string('biometric_user_id', 32);
            $table->foreignId('staff_profile_id')->nullable()->constrained('staff_profiles')->nullOnDelete();
            $table->timestamp('punched_at');
            $table->date('local_date');
            $table->string('source')->default('upload');
            // The line as it arrived, for when a time looks wrong and
            // somebody has to work out whether we or the device misread it.
            $table->string('raw', 255)->nullable();
            $table->timestamps();

            $table->unique(['school_id', 'biometric_user_id', 'punched_at']);
            // The screen reads a school's day, and B3 will read it per person.
            $table->index(['school_id', 'local_date']);
            $table->index(['staff_profile_id', 'local_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('biometric_punches');
    }
};
