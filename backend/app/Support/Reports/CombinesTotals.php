<?php

namespace App\Support\Reports;

/**
 * A report that can add its own branches together.
 *
 * Each report does this itself rather than through a generic "sum the
 * integers and guess at the rates" helper, because the rates are not alike: a
 * student attendance rate is present over students times working days, and a
 * teaching coverage rate is periods reported over periods scheduled. A helper
 * that tried to infer either would be quietly wrong at exactly the moment
 * somebody trusted it.
 */
interface CombinesTotals
{
    /**
     * @param  array<int, array<string, mixed>>  $branchTotals  one entry per branch
     * @return array<string, mixed>
     */
    public function combineTotals(array $branchTotals): array;
}
