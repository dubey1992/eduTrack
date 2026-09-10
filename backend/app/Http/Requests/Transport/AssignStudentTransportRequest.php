<?php

namespace App\Http\Requests\Transport;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class AssignStudentTransportRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('update', $this->route('student'));
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $student = $this->route('student');

        return [
            'route_id' => [
                'required', 'integer',
                Rule::exists('transport_routes', 'id')->where(fn ($query) => $query->where('school_id', $student->school_id)),
            ],
            'transport_stop_id' => [
                'required', 'integer',
                Rule::exists('transport_stops', 'id')->where(fn ($query) => $query->where('route_id', $this->input('route_id'))),
            ],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'route_id.exists' => 'The selected route does not belong to this school.',
            'transport_stop_id.exists' => 'The selected stop is not on the selected route.',
        ];
    }
}
