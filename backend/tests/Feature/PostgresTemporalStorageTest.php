<?php

namespace Tests\Feature;

use App\Models\Attendance;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * How instants are stored on PostgreSQL, pinned deliberately.
 *
 * eduTrack keeps every instant in UTC and works out each school's local day in
 * application code (docs/timezones.md), so the database must hand back exactly
 * the value it was given. `timestamp without time zone` does that.
 * `timestamptz` does not: it converts on read according to the session's
 * TimeZone, so a server or a connection configured differently would move
 * every timestamp - and for a school far enough east or west, that moves
 * attendance across a day boundary. A whole day of registers silently
 * attributed to the wrong date is not a bug anybody finds quickly.
 *
 * The twenty behavioural tests in SchoolTimezoneTest would catch the damage.
 * These two catch the *cause*, which is worth having separately because the
 * change that introduces it would look like a tidy-up: switching a column to
 * `timestamptz` reads like an improvement right up until the day it isn't.
 */
class PostgresTemporalStorageTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::connection()->getDriverName() !== 'pgsql') {
            $this->markTestSkipped('Describes PostgreSQL storage; MySQL has no timestamptz to confuse it with.');
        }
    }

    public function test_no_column_stores_a_timezone_of_its_own(): void
    {
        $offenders = DB::table('information_schema.columns')
            ->where('table_schema', 'public')
            ->whereIn('data_type', ['timestamp with time zone', 'time with time zone'])
            ->get(['table_name', 'column_name', 'data_type'])
            ->map(fn ($c) => "{$c->table_name}.{$c->column_name} ({$c->data_type})")
            ->all();

        $this->assertSame(
            [],
            $offenders,
            "These columns carry a timezone of their own. Every instant in eduTrack is UTC and every\n".
            "local day is worked out in application code, so a column that converts on read will move\n".
            "timestamps under you. See docs/timezones.md.\n",
        );
    }

    public function test_the_connection_is_pinned_to_utc(): void
    {
        // Set in config/database.php rather than left to the server, because
        // production will not be this machine.
        $this->assertSame('UTC', DB::selectOne('SHOW timezone')->TimeZone);
    }

    public function test_an_instant_comes_back_exactly_as_it_was_written(): void
    {
        $attendance = Attendance::factory()->create();
        $written = $attendance->created_at;

        $readBack = DB::table('attendances')->where('id', $attendance->id)->value('created_at');

        $this->assertSame(
            $written->format('Y-m-d H:i:s'),
            substr((string) $readBack, 0, 19),
            'The stored instant was not the one handed to the database.',
        );
    }
}
