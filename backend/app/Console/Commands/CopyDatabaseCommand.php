<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Copies every row from one database connection to another.
 *
 * The cutover tool for the PostgreSQL migration (docs/python-migration.md, M3).
 * The schema is not its problem - `php artisan migrate` builds that on the
 * target, and M1 proved the result is identical to MySQL's down to the last of
 * 399 columns. This moves the data into it.
 *
 * Deliberately not pgloader, which the plan originally called for. pgloader is
 * a Linux and macOS tool; it does not run on Windows, where this is developed,
 * and it is not installable on the shared cPanel host where the real cutover
 * has to happen. A tool that cannot run in the place it is needed is not a
 * plan. This runs wherever PHP does, which is the one thing production is
 * guaranteed to have.
 *
 * Three things it has to get right, and each is a way the migration fails
 * quietly rather than loudly:
 *
 *  - **Order.** Rows arrive in an order that satisfies the foreign keys,
 *    worked out from the target's own constraints rather than hardcoded.
 *  - **Booleans.** MySQL stores them as tinyint, so every one arrives as 0 or
 *    1, which PostgreSQL will not accept in a boolean column.
 *  - **Sequences.** PostgreSQL does not advance a sequence when a row is
 *    inserted with an explicit id. Skip this and the first record created
 *    after cutover collides with row #1.
 */
class CopyDatabaseCommand extends Command
{
    protected $signature = 'db:copy
                            {--from=mysql : Connection to read from}
                            {--to=pgsql : Connection to write to}
                            {--chunk=500 : Rows per insert}
                            {--fresh : Rebuild the target schema first, destroying everything in it}';

    protected $description = 'Copy every row from one connection to another, then verify it';

    /**
     * Tables whose contents belong to the machine rather than the school.
     *
     * `migrations` is written by the migrator itself, so copying it would
     * duplicate every row. The rest are caches, queues and sessions: transient
     * by definition, and carrying them over would move a half-finished job
     * queue into a database that has never seen the jobs.
     *
     * `personal_access_tokens` is deliberately NOT here. This copy keeps the
     * same Laravel application, so its tokens stay valid and nobody is signed
     * out. That changes at M12, where the Python backend cannot read them and
     * everybody signs in again.
     */
    private const NOT_DATA = [
        'migrations', 'cache', 'cache_locks', 'sessions',
        'jobs', 'job_batches', 'failed_jobs',
    ];

    public function handle(): int
    {
        $from = $this->option('from');
        $to = $this->option('to');

        if ($from === $to) {
            $this->error('Source and target are the same connection.');

            return self::FAILURE;
        }

        $this->line("Copying <fg=cyan>{$from}</> into <fg=cyan>{$to}</>");

        if ($this->option('fresh')) {
            $this->line('Rebuilding the target schema...');
            $this->call('migrate:fresh', ['--database' => $to, '--force' => true]);
        }

        $tables = $this->tablesInDependencyOrder($to);

        if ($tables === []) {
            $this->error("No tables on {$to}. Run the migrations first, or pass --fresh.");

            return self::FAILURE;
        }

        $this->newLine();

        try {
            $copied = $this->copy($from, $to, $tables);
        } catch (Throwable $e) {
            $this->newLine();
            $this->error('Copy failed: '.$e->getMessage());

            return self::FAILURE;
        }

        $this->newLine();
        $this->resetSequences($to, $tables);

        $this->newLine();

        return $this->verify($from, $to, $tables, $copied);
    }

    /**
     * @param  array<int, string>  $tables
     * @return array<string, int>
     */
    private function copy(string $from, string $to, array $tables): array
    {
        $copied = [];

        foreach ($tables as $table) {
            $booleans = $this->booleanColumns($to, $table);
            $written = 0;

            DB::connection($from)->table($table)->orderBy($this->orderColumn($from, $table))->chunk(
                (int) $this->option('chunk'),
                function ($rows) use ($to, $table, $booleans, &$written) {
                    $batch = [];

                    foreach ($rows as $row) {
                        $values = (array) $row;

                        // MySQL hands back 0 and 1 for what PostgreSQL calls
                        // true and false, and will not take the integers.
                        foreach ($booleans as $column) {
                            if (array_key_exists($column, $values) && $values[$column] !== null) {
                                $values[$column] = (bool) $values[$column];
                            }
                        }

                        $batch[] = $values;
                    }

                    DB::connection($to)->table($table)->insert($batch);
                    $written += count($batch);
                }
            );

            $copied[$table] = $written;
            $this->line(sprintf('  %-34s %s', $table, number_format($written)));
        }

        return $copied;
    }

    /**
     * Every sequence set past the highest id that was just imported.
     *
     * The failure this prevents does not look like a migration problem at all:
     * everything imports, every page loads, and then the first student admitted
     * collides with student #1 and the insert is refused. Asserted rather than
     * assumed, because it is invisible until somebody tries to create
     * something.
     *
     * @param  array<int, string>  $tables
     */
    private function resetSequences(string $to, array $tables): void
    {
        if (DB::connection($to)->getDriverName() !== 'pgsql') {
            $this->line('Sequences: nothing to do on this driver.');

            return;
        }

        $reset = 0;

        foreach ($tables as $table) {
            $sequence = $this->sequenceFor($to, $table);

            if ($sequence === null) {
                continue;
            }

            // is_called = true so the *next* value is max + 1, and the false
            // for an empty table so the first row still gets id 1.
            DB::connection($to)->statement(
                "SELECT setval(?, COALESCE((SELECT MAX(id) FROM {$table}), 1), (SELECT MAX(id) IS NOT NULL FROM {$table}))",
                [$sequence]
            );

            $reset++;
        }

        $this->line("Sequences reset: <fg=cyan>{$reset}</>");
    }

    /**
     * @param  array<int, string>  $tables
     * @param  array<string, int>  $copied
     */
    private function verify(string $from, string $to, array $tables, array $copied): int
    {
        $this->line('Verifying...');
        $problems = 0;

        foreach ($tables as $table) {
            $source = DB::connection($from)->table($table)->count();
            $target = DB::connection($to)->table($table)->count();

            if ($source !== $target) {
                $this->line(sprintf('  <fg=red>%-34s %s -> %s</>', $table, $source, $target));
                $problems++;
            }
        }

        // The sequences are the half nobody checks, so check them: inserting
        // is the only thing that proves one was set, and it is cheaper to find
        // out here than on a Monday morning.
        if (DB::connection($to)->getDriverName() === 'pgsql') {
            foreach ($tables as $table) {
                $sequence = $this->sequenceFor($to, $table);

                if ($sequence === null) {
                    continue;
                }

                $next = DB::connection($to)->selectOne("SELECT last_value, is_called FROM {$sequence}");
                $max = DB::connection($to)->table($table)->max('id');

                if ($max !== null && $next->last_value < $max) {
                    $this->line(sprintf('  <fg=red>%-34s sequence at %s, highest id %s</>', $table, $next->last_value, $max));
                    $problems++;
                }
            }
        }

        $rows = array_sum($copied);
        $this->newLine();
        $this->line('tables : '.count($tables));
        $this->line('rows   : '.number_format($rows));

        if ($problems === 0) {
            $this->info('verify : every table matches, every sequence is past its highest id');

            return self::SUCCESS;
        }

        $this->error("verify : {$problems} problem(s)");

        return self::FAILURE;
    }

    /**
     * Tables ordered so that a row's dependencies are always already there.
     *
     * Read from the target's own foreign keys rather than written down,
     * because a hardcoded list is wrong the moment somebody adds a table and
     * nobody remembers this file exists.
     *
     * @return array<int, string>
     */
    private function tablesInDependencyOrder(string $connection): array
    {
        // Scoped to this connection's own schema. MySQL lists every schema
        // the account can see, so a developer machine with a test database
        // beside the real one returns both - and stripping the prefix turns
        // that into the same table twice, which no amount of ordering can
        // resolve.
        $schema = $this->schemaOf($connection);

        $all = collect(DB::connection($connection)->getSchemaBuilder()->getTables($schema))
            ->pluck('name')
            ->reject(fn (string $t) => in_array($t, self::NOT_DATA, true))
            ->unique()
            ->values()
            ->all();

        $dependencies = $this->foreignKeys($connection, $all);

        $ordered = [];
        $placed = [];

        // Repeatedly take whatever has nothing left to wait for. A table that
        // references itself - schools.parent_school_id - depends on rows in
        // its own table rather than another, so it is not a cycle here.
        while (count($ordered) < count($all)) {
            $progress = false;

            foreach ($all as $table) {
                if (isset($placed[$table])) {
                    continue;
                }

                $waiting = array_filter(
                    $dependencies[$table] ?? [],
                    fn (string $parent) => $parent !== $table && ! isset($placed[$parent])
                );

                if ($waiting === []) {
                    $ordered[] = $table;
                    $placed[$table] = true;
                    $progress = true;
                }
            }

            if (! $progress) {
                // A genuine cycle between two tables. Nothing in this schema
                // has one, but guessing an order would be worse than saying so.
                $stuck = array_values(array_diff($all, array_keys($placed)));
                $this->error('Circular foreign keys between: '.implode(', ', $stuck));

                return [];
            }
        }

        return $ordered;
    }

    /**
     * @param  array<int, string>  $tables
     * @return array<string, array<int, string>>
     */
    private function foreignKeys(string $connection, array $tables): array
    {
        $schema = DB::connection($connection)->getSchemaBuilder();
        $dependencies = [];

        foreach ($tables as $table) {
            $dependencies[$table] = collect($schema->getForeignKeys($table))
                ->pluck('foreign_table')
                ->map(fn (?string $t) => $t === null ? null : (str_contains($t, '.') ? explode('.', $t)[1] : $t))
                ->filter()
                ->unique()
                ->values()
                ->all();
        }

        return $dependencies;
    }

    /**
     * The one schema this connection's tables live in.
     *
     * PostgreSQL calls it `public`; MySQL calls it the database name and has
     * no separate concept, which is why a MySQL account can see every database
     * it has rights to unless the question is narrowed like this.
     */
    private function schemaOf(string $connection): string
    {
        $database = DB::connection($connection)->getDatabaseName();

        return DB::connection($connection)->getDriverName() === 'pgsql' ? 'public' : $database;
    }

    /**
     * The sequence behind a table's id, or null if it has not got one.
     *
     * Not every table is keyed on an auto-incrementing id -
     * `password_reset_tokens` is keyed on the address - and
     * pg_get_serial_sequence raises rather than answering null when the column
     * does not exist, so the column has to be checked before the question is
     * asked.
     */
    private function sequenceFor(string $connection, string $table): ?string
    {
        $hasId = collect(DB::connection($connection)->getSchemaBuilder()->getColumns($table))
            ->pluck('name')
            ->contains('id');

        if (! $hasId) {
            return null;
        }

        return DB::connection($connection)
            ->selectOne('SELECT pg_get_serial_sequence(?, ?) AS name', [$table, 'id'])
            ?->name;
    }

    /**
     * @return array<int, string>
     */
    private function booleanColumns(string $connection, string $table): array
    {
        return collect(DB::connection($connection)->getSchemaBuilder()->getColumns($table))
            ->filter(fn (array $c) => in_array($c['type_name'] ?? '', ['bool', 'boolean', 'tinyint'], true))
            ->pluck('name')
            ->all();
    }

    /**
     * Chunking needs a stable order. Almost everything has an id; the few
     * pivot-shaped tables that do not are ordered by their first column.
     */
    private function orderColumn(string $connection, string $table): string
    {
        $columns = collect(DB::connection($connection)->getSchemaBuilder()->getColumns($table))->pluck('name');

        return $columns->contains('id') ? 'id' : (string) $columns->first();
    }
}
