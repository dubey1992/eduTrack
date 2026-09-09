<?php

namespace App\Http\Requests\StaffLeave;

use Illuminate\Foundation\Http\FormRequest;

class ReviewStaffLeaveRequest extends FormRequest
{
    /**
     * The StaffLeavePolicy::review check happens in the controller via
     * Gate::authorize() against the route-bound StaffLeave model.
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
            'remarks' => ['nullable', 'string', 'max:500'],
        ];
    }
}
