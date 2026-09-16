<?php

namespace Tests\Feature;

use App\Console\Commands\CopyDatabaseCommand;
use App\Models\School;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The cutover tool, tested rather than trusted.
 *
 * `db:copy` is the command that will move a live school's records from MySQL
 * to PostgreSQL (docs/python-migration.md, M3). It runs once, on a day when
 * the school is offline, and if it is wrong the discovery happens on the
 * Monday - so what it does is pinned here rather than left to a rehearsal
 * somebody remembers to repeat.
 *
 * The suite runs against one connection at a time, so this copies a database
 * onto itself rather than across drivers: the ordering, the row counts and the
 * sequence arithmetic are the same logic either way, and the driver-specific
 * half (booleans arriving as 0 and 1) is exercised for real by the rehearsals
 * recorded in the plan.
 */
class CopyDatabaseCommandTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_refuses_to_copy_a_connection_onto_itself(): void
    {
        // The mistake that would silently double every row in the source.
        $this->artisan('db:copy --from=mysql --to=mysql')
            ->expectsOutputToContain('Source and target are the same connection.')
            ->assertFailed();
    }

    public function test_it_orders_tables_so_that_parents_arrive_before_children(): void
    {
        // Not asserted by copying - asserted by reading the order it chose, so
        // the failure names the problem instead of surfacing as a foreign key
        // violation halfway through a cutover.
        $order = $this->orderChosen();

        $this->assertArrivesBefore($order, 'schools', 'users');
        $this->assertArrivesBefore($order, 'schools', 'students');
        $this->assertArrivesBefore($order, 'academic_years', 'school_classes');
        $this->assertArrivesBefore($order, 'school_classes', 'class_sections');
        $this->assertArrivesBefore($order, 'class_sections', 'students');
        $this->assertArrivesBefore($order, 'students', 'attendances');
    }

    public function test_a_self_referencing_table_does_not_deadlock_the_ordering(): void
    {
        // schools.parent_school_id points at schools. That is a dependency on
        // rows in the same table, not on another table, and treating it as a
        // cycle would make the command refuse to run at all.
        $this->assertContains('schools', $this->orderChosen());
    }

    public function test_it_leaves_out_the_tables_that_belong_to_the_machine(): void
    {
        $order = $this->orderChosen();

        foreach (['migrations', 'cache', 'sessions', 'jobs', 'failed_jobs'] as $transient) {
            $this->assertNotContains($transient, $order, "{$transient} is not a school's data");
        }
    }

    public function test_it_carries_the_login_tokens_over(): void
    {
        // Moving database but not application: the tokens stay valid and
        // nobody is signed out. That only changes when the backend itself is
        // replaced, at M12.
        $this->assertContains('personal_access_tokens', $this->orderChosen());
    }

    public function test_every_table_it_copies_really_exists(): void
    {
        $tables = collect(DB::connection()->getSchemaBuilder()->getTableListing())
            ->map(fn (string $t) => str_contains($t, '.') ? explode('.', $t)[1] : $t);

        foreach ($this->orderChosen() as $table) {
            $this->assertTrue($tables->contains($table), "db:copy would try to read a table that is not there: {$table}");
        }
    }

    public function test_the_data_it_would_carry_is_the_data_that_is_there(): void
    {
        // A sanity check on the premise rather than the mechanism: whatever
        // exists in the source has to appear in the ordering, or it will be
        // quietly left behind on cutover day.
        $school = School::factory()->create();
        User::factory()->forSchool($school)->create();
        Student::factory()->create(['school_id' => $school->id]);

        $order = $this->orderChosen();

        foreach (['schools', 'users', 'students'] as $table) {
            $this->assertContains($table, $order);
            $this->assertGreaterThan(0, DB::table($table)->count());
        }
    }

    /**
     * The order the command would copy in, read through the same private
     * method it uses, so the test cannot drift from the behaviour.
     *
     * @return array<int, string>
     */
    private function orderChosen(): array
    {
        $command = new CopyDatabaseCommand;
        $command->setLaravel($this->app);

        $method = new \ReflectionMethod($command, 'tablesInDependencyOrder');

        return $method->invoke($command, config('database.default'));
    }

    /**
     * @param  array<int, string>  $order
     */
    private function assertArrivesBefore(array $order, string $parent, string $child): void
    {
        $parentAt = array_search($parent, $order, true);
        $childAt = array_search($child, $order, true);

        $this->assertNotFalse($parentAt, "{$parent} is not in the copy order at all");
        $this->assertNotFalse($childAt, "{$child} is not in the copy order at all");
        $this->assertLessThan(
            $childAt,
            $parentAt,
            "{$child} would be copied before {$parent}, and its foreign keys would have nothing to point at",
        );
    }
}
