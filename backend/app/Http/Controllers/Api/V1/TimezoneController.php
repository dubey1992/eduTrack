<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use DateTimeZone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class TimezoneController extends Controller
{
    /**
     * The timezones a school can be set to.
     *
     * Reference data, not tenant data: it is the IANA list PHP ships with, so
     * the picker can never offer a zone the backend would reject. The list is
     * bounded (a few hundred entries) and identical for every user, so it is
     * returned whole rather than paginated - `q` narrows it for a search box.
     */
    public function index(Request $request): JsonResponse
    {
        $term = trim((string) $request->query('q', ''));
        $now = Carbon::now();

        $timezones = collect(DateTimeZone::listIdentifiers())
            ->when($term !== '', fn ($list) => $list->filter(
                fn (string $name) => str_contains(strtolower($name), strtolower($term))
            ))
            ->map(function (string $name) use ($now) {
                $offset = $now->copy()->setTimezone($name)->getOffset() / 60;

                return [
                    'name' => $name,
                    'region' => str_contains($name, '/') ? explode('/', $name)[0] : 'Other',
                    'offset_minutes' => (int) $offset,
                    'label' => $name.' ('.$this->offsetLabel((int) $offset).')',
                ];
            })
            ->sortBy([['offset_minutes', 'asc'], ['name', 'asc']])
            ->values();

        return response()->json(['data' => $timezones]);
    }

    /**
     * "GMT+05:30" - the form people recognise from a timezone picker.
     */
    private function offsetLabel(int $minutes): string
    {
        $sign = $minutes < 0 ? '-' : '+';
        $minutes = abs($minutes);

        return sprintf('GMT%s%02d:%02d', $sign, intdiv($minutes, 60), $minutes % 60);
    }
}
