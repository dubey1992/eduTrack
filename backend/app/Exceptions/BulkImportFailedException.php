<?php

namespace App\Exceptions;

use Exception;

/**
 * The uploaded file was not good enough to import, and nothing was written.
 *
 * Carries every problem found rather than the first, so one upload tells the
 * school everything it needs to fix.
 */
class BulkImportFailedException extends Exception
{
    /**
     * @param  array<int, array{row: int, messages: array<int, string>}>  $rowErrors
     */
    public function __construct(
        public readonly string $label,
        public readonly array $rowErrors,
        public readonly int $rowCount,
    ) {
        parent::__construct('Nothing was imported. Fix the rows below and upload the file again.');
    }
}
