<?php

namespace App\Http\Requests\Announcements;

use App\Enums\AnnouncementAudience;
use App\Enums\AnnouncementChannels;
use App\Http\Requests\Concerns\ChecksSchoolDates;
use App\Http\Requests\Concerns\ScopesSchool;
use App\Models\Announcement;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Enum;

class PublishAnnouncementRequest extends FormRequest
{
    use ChecksSchoolDates;
    use ScopesSchool;

    public function authorize(): bool
    {
        $audience = AnnouncementAudience::tryFrom((string) $this->input('audience_type'));

        if ($audience === null) {
            // Let the rules below report the bad audience as a 422.
            return $this->user()->can('viewAny', Announcement::class);
        }

        return $this->user()->can('publish', [
            Announcement::class,
            $audience,
            $this->input('audience_id') === null ? null : (int) $this->input('audience_id'),
            $this->schoolId(),
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $schoolId = $this->schoolId();

        return [
            'school_id' => $this->schoolIdRules(),
            'title' => ['required', 'string', 'min:3', 'max:150'],
            'body' => ['required', 'string', 'min:10', 'max:2000'],
            'audience_type' => ['required', new Enum(AnnouncementAudience::class)],
            'audience_id' => [
                Rule::requiredIf(fn () => $this->audience()?->needsTarget() === true),
                'nullable',
                'integer',
                // The target must belong to the acting school, so an id from
                // another school cannot be smuggled in.
                Rule::when(
                    $this->audience() === AnnouncementAudience::ClassSection,
                    [Rule::exists('class_sections', 'id')->where(
                        fn ($query) => $query->whereIn(
                            'school_class_id',
                            fn ($inner) => $inner->select('school_classes.id')
                                ->from('school_classes')
                                ->join('academic_years', 'academic_years.id', '=', 'school_classes.academic_year_id')
                                ->where('academic_years.school_id', $schoolId)
                        )
                    )]
                ),
                Rule::when(
                    $this->audience() === AnnouncementAudience::Department,
                    [Rule::exists('departments', 'id')->where('school_id', $schoolId)]
                ),
            ],
            'channels' => ['required', new Enum(AnnouncementChannels::class)],
            'expires_at' => ['nullable', 'date', $this->notInPast()],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'audience_id.required' => 'Pick the class or department this announcement is for.',
            'audience_id.exists' => 'That class or department does not belong to this school.',
            'expires_at.after_or_equal' => 'An expiry date cannot be in the past.',
        ];
    }

    public function audience(): ?AnnouncementAudience
    {
        return AnnouncementAudience::tryFrom((string) $this->input('audience_type'));
    }

    public function schoolId(): ?int
    {
        return $this->resolvedSchoolId();
    }

    /**
     * @return array<string, mixed>
     */
    public function payload(): array
    {
        return [
            ...$this->validated(),
            'school_id' => $this->schoolId(),
        ];
    }
}
