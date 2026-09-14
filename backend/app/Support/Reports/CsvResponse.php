<?php

namespace App\Support\Reports;

use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Turns a report's rows into a downloadable CSV.
 *
 * Streamed rather than built in memory: a year of attendance for a large
 * school is tens of thousands of rows, and holding all of it as one string
 * is how a report kills a shared-hosting PHP process.
 */
class CsvResponse
{
    /**
     * @param  array<int, string>  $headings
     * @param  iterable<int, array<int, mixed>>  $rows
     */
    public static function make(string $fileName, array $headings, iterable $rows): StreamedResponse
    {
        return response()->stream(function () use ($headings, $rows) {
            $handle = fopen('php://output', 'wb');

            // Excel reads a CSV as the system codepage unless the file opens
            // with a byte order mark, which mangles any non-ASCII name.
            fwrite($handle, "\xEF\xBB\xBF");

            fputcsv($handle, $headings);

            foreach ($rows as $row) {
                fputcsv($handle, array_map(self::cell(...), $row));
            }

            fclose($handle);
        }, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="'.$fileName.'"',
        ]);
    }

    /**
     * Renders one value the way a spreadsheet should read it.
     */
    private static function cell(mixed $value): string
    {
        return match (true) {
            $value === null => '-',
            is_bool($value) => $value ? 'Yes' : 'No',
            default => (string) $value,
        };
    }
}
