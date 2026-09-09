<?php

namespace App\Http\Requests\Holidays;

use App\Enums\HolidayType;
use App\Enums\UserRole;
use App\Models\Holiday;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Enum;

class StoreHolidayRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Holiday::class);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // Same null-tolerant split as StoreDepartmentRequest - a
            // non-SuperAdmin's school is always taken from their account.
            'school_id' => $this->user()->role === UserRole::SuperAdmin
                ? ['required', 'integer', 'exists:schools,id']
                : ['nullable'],
            'name' => ['required', 'string', 'max:100'],
            'type' => ['required', new Enum(HolidayType::class)],
            'start_date' => ['required', 'date'],
            'end_date' => ['required', 'date', 'after_or_equal:start_date'],
        ];
    }
}
