<?php

namespace App\Http\Requests\Attendance;

use App\Enums\AttendanceStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpdateAttendanceRequest extends FormRequest
{
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
            'class_section_id' => ['required', 'integer', Rule::exists('class_sections', 'id')],
            'attendance_date' => ['required', 'date', 'before_or_equal:today'],
            'records' => [
                'required', 'array', 'min:1',
                function ($attribute, $value, $fail) {
                    $studentIds = array_column($value, 'student_id');
                    if (count($studentIds) !== count(array_unique($studentIds))) {
                        $fail('Each student can only appear once in the attendance records.');
                    }
                },
            ],
            'records.*.student_id' => [
                'required', 'integer',
                Rule::exists('students', 'id')->where(fn ($query) => $query
                    ->where('class_section_id', $this->input('class_section_id'))
                    ->where('status', 'active')),
            ],
            'records.*.status' => ['required', new Enum(AttendanceStatus::class)],
            'records.*.remarks' => ['nullable', 'string', 'max:255'],
        ];
    }
}
