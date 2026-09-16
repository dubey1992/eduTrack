<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The work the Python backend defers, and the cron that drains it.
 *
 * Separate from Laravel's own `jobs` table, deliberately. That one holds a
 * serialized PHP object: the payload *is* the class, and nothing but PHP can
 * unserialize it. A Python worker reading those rows would have a blob it
 * cannot execute, and a PHP worker reading Python's rows would have the same
 * problem in reverse. Two producers, two formats, one table is how a queue
 * starts silently dropping work.
 *
 * So this is a second, simpler table with a JSON payload and a job name -
 * readable by anything, and by design the shape a cron-driven worker needs
 * rather than a broker-driven one. Hosting is cPanel (docs/python-migration.md,
 * M0), which offers cron and no broker; that is not a limitation being worked
 * around here, it is the requirement.
 *
 * Created by a Laravel migration even though only the Python backend uses it,
 * because Laravel's migrations own this schema until the cutover. Letting
 * Django create one table would put a table in PostgreSQL that MySQL does not
 * have, and `schema:diff` - the check that proved the two databases identical
 * at M1 - would be right to complain.
 *
 * Laravel never writes to it. It is empty on this backend and stays that way.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('queued_jobs', function (Blueprint $table) {
            $table->id();

            // Which queue this belongs to. One today; named queues exist so a
            // slow bulk job can never sit in front of a receipt.
            $table->string('queue', 64)->default('default');

            // What to run, by name - not a serialized object. The worker maps
            // the name to a handler, so a payload written by one version is
            // still readable by the next.
            $table->string('name', 100);

            // The handler's arguments, as JSON. Ids rather than records: a job
            // that carried a copy of a payment would act on what was true when
            // it was queued rather than what is true when it runs.
            $table->json('payload');

            $table->unsignedSmallInteger('attempts')->default(0);

            // The last thing that went wrong, kept on the row rather than only
            // in a log: whoever is looking at a stuck job is looking at the
            // table.
            $table->text('last_error')->nullable();

            // When it may first run. Now, for most things; later for a retry
            // backing off.
            $table->timestamp('available_at');

            // Set while a worker holds the row, cleared when it finishes. A
            // crashed worker leaves this set, which is what makes a stuck job
            // visible rather than invisible.
            $table->timestamp('reserved_at')->nullable();

            $table->timestamps();

            // The worker's only query: the next unreserved job on this queue
            // that is due.
            $table->index(['queue', 'reserved_at', 'available_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('queued_jobs');
    }
};
