<?php

namespace App\Support\Reports;

use App\Models\School;
use Illuminate\Support\Collection;

/**
 * One report run across every branch in a group.
 *
 * Deliberately not one big query with a `whereIn`. Every branch has its own
 * holiday calendar and its own timezone, so "the working days in September"
 * is a different number at each of them - and every percentage in a report is
 * measured against that number. Running the report once per branch and
 * stitching the results is the only way the figures stay true.
 *
 * Which also means a group total can never be an average of the branches'
 * percentages: a branch of forty and a branch of four hundred would weigh the
 * same. The combined rate is recomputed from raw counts, and each report does
 * that arithmetic itself - see CombinesTotals.
 */
class GroupReport
{
    /**
     * @param  Collection<int, School>  $schools
     * @param  callable(School): array<string, mixed>  $forSchool
     * @return array<string, mixed>
     */
    public static function build(Collection $schools, callable $forSchool, CombinesTotals $report): array
    {
        $branches = $schools->map(function (School $school) use ($forSchool) {
            $built = $forSchool($school);

            return [
                'school_id' => $school->id,
                'school_name' => $school->name,
                'range' => $built['range'],
                'totals' => $built['totals'],
                'rows' => $built['rows'],
            ];
        });

        // Every row carries the branch it came from, so one flat table can be
        // read - and sorted, and exported - without losing which school a
        // line belongs to.
        $rows = $branches
            ->flatMap(fn (array $branch) => array_map(
                fn (array $row) => ['school_id' => $branch['school_id'], 'school_name' => $branch['school_name'], ...$row],
                $branch['rows'],
            ))
            ->values();

        return [
            'group' => true,
            'range' => self::widestRange($branches),
            'branches' => $branches
                ->map(fn (array $branch) => [
                    'school_id' => $branch['school_id'],
                    'school_name' => $branch['school_name'],
                    'range' => $branch['range'],
                    'totals' => $branch['totals'],
                ])
                ->values()
                ->all(),
            'rows' => $rows->all(),
            'totals' => $report->combineTotals($branches->pluck('totals')->all()),
        ];
    }

    /**
     * The window the group as a whole covers.
     *
     * Branches can differ by a day at the edges - a range defaults to "up to
     * today at the school", and two branches in different timezones need not
     * agree on what today is. The widest pair is the honest answer, and the
     * per-branch ranges are reported alongside it.
     *
     * `working_days` is deliberately absent: it is a property of one school's
     * calendar, and adding two schools' working days together would be a
     * number that means nothing.
     *
     * @param  Collection<int, array<string, mixed>>  $branches
     * @return array<string, mixed>
     */
    private static function widestRange(Collection $branches): array
    {
        $ranges = $branches->pluck('range');

        return [
            'from' => $ranges->pluck('from')->filter()->min(),
            'to' => $ranges->pluck('to')->filter()->max(),
        ];
    }
}
