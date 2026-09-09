<?php

namespace App\Http\Requests\Holidays;

use App\Enums\HolidayType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rules\Enum;

class UpdateHolidayRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('holiday'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $holiday = $this->route('holiday');

        // Either date may be sent alone, so the ordering check compares
        // against whichever side isn't in the request.
        $start = $this->input('start_date', $holiday->start_date->toDateString());
        $end = $this->input('end_date', $holiday->end_date->toDateString());
        $ordered = function ($attribute, $value, $fail) use ($start, $end) {
            if (strtotime($start) !== false && strtotime($end) !== false && Carbon::parse($end)->lt(Carbon::parse($start))) {
                $fail('The end date must be on or after the start date.');
            }
        };

        return [
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'type' => ['sometimes', 'required', new Enum(HolidayType::class)],
            'start_date' => ['sometimes', 'required', 'date', $ordered],
            'end_date' => ['sometimes', 'required', 'date', $ordered],
        ];
    }
}
