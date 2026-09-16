<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Compares two database connections table by table and column by column.
 *
 * Built for the PostgreSQL migration (docs/python-migration.md): "the
 * migrations ran without erroring" is not the same claim as "the schema is the
 * same", and only the second one is worth anything. Kept rather than thrown
 * away because phases M3 and M4 both have to make that claim again, against
 * real data and on every commit.
 *
 * It compares what the two dialects *mean*, not what they call it - a MySQL
 * `varchar(255)` and a Postgres `character varying(255)` are the same column,
 * and reporting them as a difference would bury the ones that matter.
 */
class SchemaDiffCommand extends Command
{
    protected $signature = 'schema:diff
                            {--from=mysql : The connection to treat as the original}
                            {--to=pgsql : The connection to compare against it}';

    protected $description = 'Compare two connections column by column, ignoring dialect spelling';

    /** Tables that belong to the framework rather than the product. */
    private const IGNORED = ['migrations'];

    public function handle(): int
    {
        $from = $this->option('from');
        $to = $this->option('to');

        $left = $this->columns($from);
        $right = $this->columns($to);

        $tables = array_unique([...array_keys($left), ...array_keys($right)]);
        sort($tables);

        $differences = 0;
        $tableCount = 0;
        $columnCount = 0;

        foreach ($tables as $table) {
            if (in_array($table, self::IGNORED, true)) {
                continue;
            }

            if (! isset($left[$table])) {
                $this->line("  <fg=red>table only in {$to}:</> {$table}");
                $differences++;

                continue;
            }

            if (! isset($right[$table])) {
                $this->line("  <fg=red>table only in {$from}:</> {$table}");
                $differences++;

                continue;
            }

            $tableCount++;
            $columns = array_unique([...array_keys($left[$table]), ...array_keys($right[$table])]);

            foreach ($columns as $column) {
                $differences += $this->compare($table, $column, $left[$table][$column] ?? null, $right[$table][$column] ?? null, $from, $to);
                $columnCount++;
            }
        }

        $this->newLine();
        $this->line("tables compared  : {$tableCount}");
        $this->line("columns compared : {$columnCount}");

        if ($differences === 0) {
            $this->info("differences      : 0 - {$from} and {$to} agree");

            return self::SUCCESS;
        }

        $this->error("differences      : {$differences}");

        return self::FAILURE;
    }

    /**
     * @param  array{type: string, raw: string, null: bool}|null  $left
     * @param  array{type: string, raw: string, null: bool}|null  $right
     */
    private function compare(string $table, string $column, ?array $left, ?array $right, string $from, string $to): int
    {
        if ($left === null) {
            $this->line("  <fg=red>{$table}.{$column}</>: only in {$to}");

            return 1;
        }

        if ($right === null) {
            $this->line("  <fg=red>{$table}.{$column}</>: only in {$from}");

            return 1;
        }

        $found = 0;

        if ($left['type'] !== $right['type']) {
            $this->line("  <fg=red>{$table}.{$column}</>: type {$from}={$left['raw']} ({$left['type']}), {$to}={$right['raw']} ({$right['type']})");
            $found++;
        }

        if ($left['null'] !== $right['null']) {
            $leftNull = $left['null'] ? 'nullable' : 'not null';
            $rightNull = $right['null'] ? 'nullable' : 'not null';
            $this->line("  <fg=red>{$table}.{$column}</>: {$from}={$leftNull}, {$to}={$rightNull}");
            $found++;
        }

        return $found;
    }

    /**
     * @return array<string, array<string, array{type: string, raw: string, null: bool}>>
     */
    private function columns(string $connection): array
    {
        $driver = DB::connection($connection)->getDriverName();

        // MySQL's data_type says "tinyint" for both a boolean and a small
        // number; only column_type tells them apart. Postgres has no such
        // column, and no such ambiguity.
        $typeColumn = $driver === 'mysql' ? 'column_type' : 'data_type';
        $schema = $driver === 'mysql'
            ? DB::connection($connection)->getDatabaseName()
            : 'public';

        $rows = DB::connection($connection)->select("
            SELECT table_name, column_name, {$typeColumn} AS data_type, is_nullable,
                   character_maximum_length AS len,
                   numeric_precision AS p, numeric_scale AS s
            FROM information_schema.columns
            WHERE table_schema = ?
            ORDER BY table_name, ordinal_position
        ", [$schema]);

        $columns = [];

        foreach ($rows as $row) {
            // MySQL's information_schema answers in uppercase and Postgres's
            // in lowercase. Same data, different shouting.
            $r = array_change_key_case((array) $row, CASE_LOWER);

            $columns[$r['table_name']][$r['column_name']] = [
                'type' => $this->canonical($r['data_type'], $r['len'], $r['p'], $r['s']),
                'raw' => $r['data_type'],
                'null' => strtoupper((string) $r['is_nullable']) === 'YES',
            ];
        }

        return $columns;
    }

    /** Reduce each dialect's spelling of a type to one shared name. */
    private function canonical(string $type, ?int $length, ?int $precision, ?int $scale): string
    {
        $name = strtolower($type);

        // column_type carries the length inline (varchar(255), decimal(12,2)),
        // which the length handling below owns instead. tinyint(1) is the one
        // case where that suffix carries meaning rather than width.
        if ($name !== 'tinyint(1)') {
            $name = trim(str_replace(' unsigned', '', (string) preg_replace('/\(.*$/', '', $name)));
        }

        $name = match ($name) {
            'int8' => 'bigint',
            'integer', 'int4' => 'int',
            'int2' => 'smallint',
            'tinyint' => 'smallint',
            'character varying' => 'varchar',
            'character', 'bpchar' => 'char',
            'longtext', 'mediumtext' => 'text',
            'tinyint(1)', 'boolean', 'bool' => 'bool',
            'datetime', 'timestamp without time zone' => 'timestamp',
            'timestamp with time zone' => 'timestamptz',
            'time without time zone' => 'time',
            'decimal' => 'numeric',
            'double', 'double precision' => 'float',
            'jsonb' => 'json',
            default => $name,
        };

        return match ($name) {
            'varchar', 'char' => $name.'('.($length ?? '?').')',
            'numeric' => 'numeric('.($precision ?? '?').','.($scale ?? '?').')',
            default => $name,
        };
    }
}
