<?php

namespace App\Services\Imports;

use App\Exceptions\BulkImportFailedException;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Reads an uploaded CSV and turns it into records - or into a list of
 * everything wrong with it.
 *
 * Nothing is written until every row has passed. A file of two hundred
 * students with a mistake on row seven imports none of them and says so,
 * because the alternative - a hundred and ninety-nine rows in and one to
 * chase - leaves the school reconciling a half-finished import, and makes
 * re-uploading the corrected file duplicate everything that already landed.
 */
class BulkImportService
{
    /** Enough for a large school's whole roll, small enough to stay in memory. */
    private const int MAX_ROWS = 2000;

    /**
     * @return array<string, mixed>
     */
    public function import(RowImporter $importer, UploadedFile $file, int $schoolId, User $actor): array
    {
        $rows = $this->read($file, $importer);
        $errors = $this->validate($rows, $importer, $schoolId);

        if ($errors !== []) {
            throw new BulkImportFailedException($importer->label(), $errors, count($rows));
        }

        // Every row is known good by here, so the transaction is about
        // atomicity against a database failure rather than validation.
        $created = DB::transaction(function () use ($rows, $importer, $schoolId, $actor) {
            $results = [];

            foreach ($rows as $row) {
                $result = $importer->import($row['data'], $schoolId, $actor);

                if ($result !== null) {
                    $results[] = $result;
                }
            }

            return $results;
        });

        return [
            'imported' => count($rows),
            'label' => $importer->label(),
            'details' => $created,
        ];
    }

    /**
     * Parses the file into rows, each remembering the line it came from so an
     * error can point at a line in the spreadsheet rather than an index.
     *
     * @return array<int, array{line: int, data: array<string, string|null>}>
     */
    private function read(UploadedFile $file, RowImporter $importer): array
    {
        $handle = fopen($file->getRealPath(), 'rb');

        if ($handle === false) {
            throw new BulkImportFailedException($importer->label(), [
                ['row' => 0, 'messages' => ['The file could not be read.']],
            ], 0);
        }

        $headings = fgetcsv($handle);

        if ($headings === false) {
            fclose($handle);

            throw new BulkImportFailedException($importer->label(), [
                ['row' => 0, 'messages' => ['The file is empty. Download the template and fill it in.']],
            ], 0);
        }

        // A byte order mark - which is what a spreadsheet writes - would
        // otherwise make the first column name never match.
        $headings[0] = preg_replace('/^\xEF\xBB\xBF/', '', (string) $headings[0]);
        $headings = array_map(static fn ($heading) => trim((string) $heading), $headings);

        $expected = $importer->headings();

        if ($headings !== $expected) {
            fclose($handle);

            throw new BulkImportFailedException($importer->label(), [
                [
                    'row' => 1,
                    'messages' => [
                        'The column headings do not match the template. Expected: '.implode(', ', $expected).'.',
                    ],
                ],
            ], 0);
        }

        $rows = [];
        $line = 1;

        while (($values = fgetcsv($handle)) !== false) {
            $line++;

            // A trailing blank line is what every spreadsheet leaves behind;
            // it is not a row anybody meant to add.
            if ($values === [null] || $values === [''] || $this->isBlank($values)) {
                continue;
            }

            $values = array_pad(array_slice($values, 0, count($expected)), count($expected), null);
            $data = array_combine($expected, array_map([$this, 'clean'], $values));

            $rows[] = ['line' => $line, 'data' => $data];

            if (count($rows) > self::MAX_ROWS) {
                fclose($handle);

                throw new BulkImportFailedException($importer->label(), [
                    [
                        'row' => $line,
                        'messages' => ['A file can hold at most '.self::MAX_ROWS.' rows. Split it and upload again.'],
                    ],
                ], 0);
            }
        }

        fclose($handle);

        if ($rows === []) {
            throw new BulkImportFailedException($importer->label(), [
                ['row' => 1, 'messages' => ['The file has headings but no rows.']],
            ], 0);
        }

        return $rows;
    }

    /**
     * Validates every row, and reports every failure rather than stopping at
     * the first - a file with ten mistakes should take one upload to find
     * them all, not ten.
     *
     * @param  array<int, array{line: int, data: array<string, string|null>}>  $rows
     * @return array<int, array{row: int, messages: array<int, string>}>
     */
    private function validate(array $rows, RowImporter $importer, int $schoolId): array
    {
        $errors = [];
        $rules = $importer->rules($schoolId);
        $seen = [];

        foreach ($rows as $row) {
            $validator = Validator::make($row['data'], $rules);
            $messages = $validator->fails() ? $this->flatten($validator->errors()->toArray()) : [];

            // Cross-column checks only make sense once the columns
            // themselves are known good - otherwise a blank class produces
            // both "the class is required" and "that class has no such
            // section".
            if ($messages === []) {
                $messages = $importer->check($row['data'], $schoolId);
            }

            // Duplicates inside the file itself. The database catches a clash
            // with an existing record; nothing catches the same admission
            // number typed twice in the spreadsheet being uploaded.
            foreach ($importer->uniqueColumns() as $column) {
                $value = $row['data'][$column] ?? null;

                if ($value === null || $value === '') {
                    continue;
                }

                $key = $column.'|'.mb_strtolower($value);

                if (isset($seen[$key])) {
                    $messages[] = "The {$column} \"{$value}\" is also on row {$seen[$key]}.";
                } else {
                    $seen[$key] = $row['line'];
                }
            }

            if ($messages !== []) {
                $errors[] = ['row' => $row['line'], 'messages' => array_values($messages)];
            }
        }

        return $errors;
    }

    /**
     * @param  array<string, array<int, string>>  $errors
     * @return array<int, string>
     */
    private function flatten(array $errors): array
    {
        return array_merge(...array_values($errors));
    }

    /**
     * @param  array<int, string|null>  $values
     */
    private function isBlank(array $values): bool
    {
        foreach ($values as $value) {
            if (trim((string) $value) !== '') {
                return false;
            }
        }

        return true;
    }

    /**
     * An empty cell is nothing, not an empty string - otherwise a `nullable`
     * column would fail its own format rule on a blank.
     */
    private function clean(mixed $value): ?string
    {
        $value = trim((string) $value);

        return $value === '' ? null : $value;
    }
}
