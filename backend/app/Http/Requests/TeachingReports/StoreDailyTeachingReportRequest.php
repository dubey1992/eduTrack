<?php

namespace App\Http\Requests\TeachingReports;

use App\Models\TimetableEntry;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Carbon;

class StoreDailyTeachingReportRequest extends FormRequest
{
    /**
     * Structural validity only - does this timetable entry exist at all.
     * Whether it's actually *this actor's* period is an ownership/
     * authorization concern, checked by DailyTeachingReportPolicy::create()
     * in the controller (403), not folded into validation (422) here.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'timetable_entry_id' => ['required', 'integer', 'exists:timetable_entries,id'],
            'report_date' => [
                'required', 'date', 'before_or_equal:today',
                function ($attribute, $value, $fail) {
                    $entry = TimetableEntry::find($this->input('timetable_entry_id'));
                    if ($entry === null) {
                        return;
                    }

                    $dayOfWeek = strtolower(Carbon::parse($value)->format('l'));
                    if ($dayOfWeek !== $entry->day_of_week->value) {
                        $fail('The report date must fall on the day this period is scheduled ('.ucfirst($entry->day_of_week->value).').');
                    }
                },
            ],
            'topic_taught' => ['required', 'string', 'max:255'],
            'homework' => ['nullable', 'string', 'max:500'],
            'remarks' => ['nullable', 'string', 'max:500'],
        ];
    }
}
