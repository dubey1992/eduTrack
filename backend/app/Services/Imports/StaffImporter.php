<?php

namespace App\Services\Imports;

use App\Models\Department;
use App\Models\User;
use App\Rules\MatchesIgnoringCase;
use App\Services\StaffProfileService;
use App\Support\DateFormats;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Teachers and staff, one row each.
 *
 * Nobody types a password into a spreadsheet - it would sit in the school
 * office's downloads folder in plain text for as long as the file survives.
 * Each account gets a generated one instead, handed back once to whoever ran
 * the import, and marked as needing a change at the first sign-in.
 */
class StaffImporter implements RowImporter
{
    /** The roles this can create - never an admin account. */
    private const array ROLES = ['HOD', 'TEACHER', 'STAFF', 'TRANSPORT_MANAGER'];

    /** @var array<string, int>|null Department name to id. */
    private ?array $departments = null;

    public function __construct(private readonly StaffProfileService $staff) {}

    public function label(): string
    {
        return 'Teachers and Staff';
    }

    public function headings(): array
    {
        return [
            'employee_id', 'first_name', 'last_name', 'email', 'mobile',
            'role', 'department', 'designation', 'joining_date', 'address',
        ];
    }

    public function sample(): array
    {
        return [
            'EMP-1042', 'Priya', 'Nair', 'priya.nair@example.com', '+91 98765 43210',
            'TEACHER', 'Science', 'Senior Teacher', '09/14/2026', '22 Hill Road, Pune',
        ];
    }

    public function rules(int $schoolId): array
    {
        return [
            'employee_id' => [
                'required', 'string', 'max:30',
                Rule::unique('staff_profiles', 'employee_id')->where(fn ($query) => $query->where('school_id', $schoolId)),
            ],
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            // Addresses are stored lowercase, so "Priya.Nair@" is the account
            // "priya.nair@" already holds.
            'email' => ['required', 'email', 'max:255', MatchesIgnoringCase::unique(User::query(), 'email')],
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            // Spelt out rather than Rule::in so "Teacher" works as well as
            // "TEACHER" - a spreadsheet cell is not a dropdown.
            'role' => ['required', 'string', function (string $attribute, mixed $value, callable $fail) {
                if (! in_array(mb_strtoupper(trim((string) $value)), self::ROLES, true)) {
                    $fail('The role must be one of: '.implode(', ', self::ROLES).'.');
                }
            }],
            'department' => [
                'nullable', 'string',
                MatchesIgnoringCase::exists(Department::query()->where('school_id', $schoolId), 'name'),
            ],
            'designation' => ['nullable', 'string', 'max:100'],
            'joining_date' => ['required', 'date_format:'.DateFormats::INPUT_DATES],
            'address' => ['nullable', 'string', 'max:500'],
        ];
    }

    public function uniqueColumns(): array
    {
        return ['employee_id', 'email'];
    }

    public function check(array $row, int $schoolId): array
    {
        return [];
    }

    public function import(array $row, int $schoolId, User $actor): ?array
    {
        // Long, random, and never seen by whoever prepared the file - only by
        // whoever ran the import, once, in the response.
        $password = Str::password(14);

        $profile = $this->staff->createEmployee(
            [
                'school_id' => $schoolId,
                'first_name' => $row['first_name'],
                'last_name' => $row['last_name'],
                'email' => $row['email'],
                'mobile' => $row['mobile'],
                'password' => $password,
                'role' => mb_strtoupper(trim((string) $row['role'])),
                'must_change_password' => true,
            ],
            [
                'employee_id' => $row['employee_id'],
                'department_id' => $this->departmentId($row['department'], $schoolId),
                'designation' => $row['designation'],
                'joining_date' => DateFormats::toIso((string) $row['joining_date']),
                'address' => $row['address'],
            ],
            $actor,
        );

        return [
            'id' => $profile->user_id,
            'name' => $profile->user->first_name.' '.$profile->user->last_name,
            'email' => $profile->user->email,
            'temporary_password' => $password,
        ];
    }

    private function departmentId(?string $name, int $schoolId): ?int
    {
        if ($name === null) {
            return null;
        }

        if ($this->departments === null) {
            $this->departments = Department::query()
                ->where('school_id', $schoolId)
                ->pluck('id', 'name')
                ->mapWithKeys(fn (int $id, string $department) => [mb_strtolower($department) => $id])
                ->all();
        }

        return $this->departments[mb_strtolower(trim($name))] ?? null;
    }
}
