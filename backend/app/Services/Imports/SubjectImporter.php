<?php

namespace App\Services\Imports;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\User;
use App\Rules\MatchesIgnoringCase;
use App\Services\SubjectService;
use Illuminate\Validation\Rule;

/**
 * The subject catalogue, by department name and - where there is one - the
 * email of the teacher who leads it.
 */
class SubjectImporter implements RowImporter
{
    /** @var array<string, int>|null Department name to id. */
    private ?array $departments = null;

    /** @var array<string, int>|null Teacher email to user id. */
    private ?array $teachers = null;

    public function __construct(private readonly SubjectService $subjects) {}

    public function label(): string
    {
        return 'Subjects';
    }

    public function headings(): array
    {
        return ['code', 'name', 'department', 'min_class_level', 'max_class_level', 'lead_teacher_email'];
    }

    public function sample(): array
    {
        return ['SCI-05', 'Science', 'Science', '5', '8', 'priya.nair@example.com'];
    }

    public function rules(int $schoolId): array
    {
        return [
            'code' => [
                'required', 'string', 'max:20',
                Rule::unique('subjects', 'code')->where(fn ($query) => $query->where('school_id', $schoolId)),
            ],
            'name' => ['required', 'string', 'max:100'],
            'department' => [
                'required', 'string',
                MatchesIgnoringCase::exists(Department::query()->where('school_id', $schoolId), 'name'),
            ],
            'min_class_level' => ['required', 'integer', 'min:0', 'max:12'],
            'max_class_level' => ['required', 'integer', 'min:0', 'max:12'],
            'lead_teacher_email' => [
                // bail: an address that is not an address is not also "not found".
                'bail', 'nullable', 'email',
                MatchesIgnoringCase::exists(
                    User::query()->where('school_id', $schoolId)->whereIn('role', [UserRole::Hod->value, UserRole::Teacher->value]),
                    'email',
                ),
            ],
        ];
    }

    public function uniqueColumns(): array
    {
        return ['code'];
    }

    public function check(array $row, int $schoolId): array
    {
        if ((int) $row['max_class_level'] < (int) $row['min_class_level']) {
            return ['The max class level must be at or above the min class level.'];
        }

        return [];
    }

    public function import(array $row, int $schoolId, User $actor): ?array
    {
        $subject = $this->subjects->create([
            'school_id' => $schoolId,
            'department_id' => $this->departmentId((string) $row['department'], $schoolId),
            'code' => $row['code'],
            'name' => $row['name'],
            'min_class_level' => (int) $row['min_class_level'],
            'max_class_level' => (int) $row['max_class_level'],
            'lead_teacher_id' => $this->teacherId($row['lead_teacher_email'], $schoolId),
        ], $actor);

        return ['id' => $subject->id, 'name' => $subject->name];
    }

    private function departmentId(string $name, int $schoolId): ?int
    {
        if ($this->departments === null) {
            $this->departments = Department::query()
                ->where('school_id', $schoolId)
                ->pluck('id', 'name')
                ->mapWithKeys(fn (int $id, string $department) => [mb_strtolower($department) => $id])
                ->all();
        }

        return $this->departments[mb_strtolower(trim($name))] ?? null;
    }

    private function teacherId(?string $email, int $schoolId): ?int
    {
        if ($email === null) {
            return null;
        }

        if ($this->teachers === null) {
            $this->teachers = User::query()
                ->where('school_id', $schoolId)
                ->whereIn('role', [UserRole::Hod, UserRole::Teacher])
                ->pluck('id', 'email')
                ->mapWithKeys(fn (int $id, string $address) => [mb_strtolower($address) => $id])
                ->all();
        }

        return $this->teachers[mb_strtolower(trim($email))] ?? null;
    }
}
