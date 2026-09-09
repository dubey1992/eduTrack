<?php

namespace App\Http\Requests\Periods;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdatePeriodRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('period'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $period = $this->route('period');

        return [
            'period_number' => [
                'sometimes', 'required', 'integer', 'min:1', 'max:20',
                Rule::unique('periods', 'period_number')
                    ->where(fn ($query) => $query->where('school_id', $period->school_id))
                    ->ignore($period->id),
            ],
            'start_time' => ['sometimes', 'required', 'date_format:H:i'],
            'end_time' => ['sometimes', 'required', 'date_format:H:i', 'after:start_time'],
        ];
    }
}
