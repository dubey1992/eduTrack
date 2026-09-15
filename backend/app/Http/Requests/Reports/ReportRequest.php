<?php

namespace App\Http\Requests\Reports;

use App\Http\Requests\Concerns\ChecksSchoolDates;
use App\Http\Requests\Concerns\ScopesSchool;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Shared shape for every report: which school, over what range, in what
 * format.
 *
 * A Super Admin spans schools and so must name one; everybody else is scoped
 * to their own school server-side and cannot ask for another - see
 * ReportController, which never reads school_id from a school user.
 */
class ReportRequest extends FormRequest
{
    use ChecksSchoolDates;
    use ScopesSchool;

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
            'school_id' => $this->readableSchoolIdRules(),
            // A report covers days that have happened. Asking for next month
            // would report everybody as absent for days nobody has taught.
            'from' => ['nullable', 'date', $this->notInFuture()],
            'to' => ['nullable', 'date', $this->notInFuture(), 'after_or_equal:from'],
            'class_section_id' => ['nullable', 'integer', Rule::exists('class_sections', 'id')],
            'department_id' => ['nullable', 'integer', Rule::exists('departments', 'id')],
            'format' => ['nullable', Rule::in(['json', 'csv'])],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'school_id.required' => 'Pick a school to report on.',
            'from.before_or_equal' => 'A report cannot start on a date that has not happened yet.',
            'to.before_or_equal' => 'A report cannot run past today.',
            'to.after_or_equal' => 'The end of the range must not be before its start.',
        ];
    }

    public function wantsCsv(): bool
    {
        return $this->query('format') === 'csv';
    }
}
