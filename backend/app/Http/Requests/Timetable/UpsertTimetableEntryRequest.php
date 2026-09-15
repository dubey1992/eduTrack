<?php

namespace App\Http\Requests\Timetable;

use App\Enums\DayOfWeek;
use App\Enums\UserRole;
use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\SchoolClass;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Collection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class UpsertTimetableEntryRequest extends FormRequest
{
    use ScopesSchool;

    /**
     * school_id is body data here, not a route-bound model - same
     * reasoning as StaffAttendance's requests: a bad id fails validation
     * (422), ownership is checked in the controller once it's confirmed
     * real (see TimetableController::resolveSchool()).
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
            'school_id' => $this->schoolIdRules(),
            'class_section_id' => [
                'required', 'integer',
                Rule::exists('class_sections', 'id')->where(function ($query) {
                    $query->whereIn('school_class_id', $this->schoolClassIdsQuery());
                }),
            ],
            'period_id' => [
                'required', 'integer',
                Rule::exists('periods', 'id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'day_of_week' => ['required', new Enum(DayOfWeek::class)],
            'subject_id' => [
                'required', 'integer',
                Rule::exists('subjects', 'id')->where(fn ($query) => $query->where('school_id', $this->resolvedSchoolId())),
            ],
            'teacher_id' => [
                'required', 'integer',
                Rule::exists('users', 'id')->where(function ($query) {
                    $query->where('school_id', $this->resolvedSchoolId())
                        ->whereIn('role', [UserRole::Teacher->value, UserRole::Hod->value]);
                }),
            ],
        ];
    }

    /**
     * class_sections has no school_id column of its own - ownership is via
     * school_classes, so the exists() check joins through that instead of
     * a plain where().
     *
     * @return Collection<int, int>
     */
    private function schoolClassIdsQuery()
    {
        return SchoolClass::query()->where('school_id', $this->resolvedSchoolId())->pluck('id');
    }
}
