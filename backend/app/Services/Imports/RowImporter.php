<?php

namespace App\Services\Imports;

use App\Models\User;

/**
 * One kind of thing a school can upload in bulk.
 *
 * Each importer says what its columns are, how a row is validated and how one
 * row becomes a record. Everything else - reading the file, checking the
 * headings, validating every row before writing any of them, and reporting
 * what was wrong - is the same for all of them and lives in
 * BulkImportService.
 */
interface RowImporter
{
    /** "Students" - what the file contains, for messages and the filename. */
    public function label(): string;

    /**
     * The columns the file must have, in order.
     *
     * @return array<int, string>
     */
    public function headings(): array;

    /**
     * One example row, written into the downloadable template so nobody has
     * to guess what a date or a phone number should look like.
     *
     * @return array<int, string>
     */
    public function sample(): array;

    /**
     * Validation for a single row.
     *
     * @return array<string, mixed>
     */
    public function rules(int $schoolId): array;

    /**
     * Columns that must not repeat within one file.
     *
     * The database catches a clash with a record that already exists;
     * nothing catches the same admission number appearing twice in the
     * spreadsheet somebody is about to upload.
     *
     * @return array<int, string>
     */
    public function uniqueColumns(): array;

    /**
     * Checks that need to see more than one column at a time - a class and a
     * section that have to name a section existing together, say.
     *
     * Only runs once a row's own rules have passed, so it never has to
     * defend against a missing or misspelt column.
     *
     * @param  array<string, mixed>  $row
     * @return array<int, string> One message per problem; empty when fine.
     */
    public function check(array $row, int $schoolId): array;

    /**
     * Creates one record from one validated row.
     *
     * @param  array<string, mixed>  $row
     * @return array<string, mixed>|null Anything the caller needs to hand
     *                                   back, such as a generated password.
     */
    public function import(array $row, int $schoolId, User $actor): ?array;
}
