<?php

namespace App\Services\Imports;

use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\User;
use App\Services\StudentService;
use Illuminate\Validation\Rule;

/**
 * A roll of students, as a school keeps it: a class and a section by name,
 * never the section id the API uses. Nobody filling in a spreadsheet knows
 * that a section is number 37.
 */
class StudentImporter implements RowImporter
{
    /** @var array<string, int>|null Class and section name to section id. */
    private ?array $sections = null;

    public function __construct(private readonly StudentService $students) {}

    public function label(): string
    {
        return 'Students';
    }

    public function headings(): array
    {
        return [
            'admission_number', 'first_name', 'last_name', 'class', 'section',
            'roll_number', 'guardian_name', 'guardian_mobile', 'address',
        ];
    }

    public function sample(): array
    {
        return [
            'ADM-2026-001', 'Aarav', 'Sharma', 'Grade 5', 'A',
            '12', 'Meera Sharma', '+91 98765 43210', '14 Rose Lane, Pune',
        ];
    }

    public function rules(int $schoolId): array
    {
        return [
            'admission_number' => [
                'required', 'string', 'max:30',
                Rule::unique('students', 'admission_number')->where(fn ($query) => $query->where('school_id', $schoolId)),
            ],
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'class' => ['required', 'string', 'max:50'],
            'section' => ['required', 'string', 'max:10'],
            'roll_number' => ['nullable', 'string', 'max:20'],
            'guardian_name' => ['required', 'string', 'max:150'],
            'guardian_mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'address' => ['nullable', 'string', 'max:500'],
        ];
    }

    public function uniqueColumns(): array
    {
        return ['admission_number'];
    }

    public function check(array $row, int $schoolId): array
    {
        if ($this->sectionId($row, $schoolId) !== null) {
            return [];
        }

        $sections = $this->sections($schoolId);

        if ($sections === []) {
            return ['This school has no classes in its current academic year yet. Set one up before importing students.'];
        }

        return ["There is no section \"{$row['section']}\" in class \"{$row['class']}\"."];
    }

    public function import(array $row, int $schoolId, User $actor): ?array
    {
        $student = $this->students->create([
            'school_id' => $schoolId,
            'class_section_id' => $this->sectionId($row, $schoolId),
            'admission_number' => $row['admission_number'],
            'first_name' => $row['first_name'],
            'last_name' => $row['last_name'],
            'roll_number' => $row['roll_number'],
            'guardian_name' => $row['guardian_name'],
            'guardian_mobile' => $row['guardian_mobile'],
            'address' => $row['address'],
        ], $actor);

        return ['id' => $student->id, 'name' => $student->first_name.' '.$student->last_name];
    }

    /**
     * @param  array<string, mixed>  $row
     */
    private function sectionId(array $row, int $schoolId): ?int
    {
        return $this->sections($schoolId)[$this->key((string) $row['class'], (string) $row['section'])] ?? null;
    }

    /**
     * The sections of the school's current academic year - the year students
     * are being enrolled into. Class names repeat from one year to the next,
     * so without that anchor "Grade 5 / A" would be ambiguous.
     *
     * @return array<string, int>
     */
    private function sections(int $schoolId): array
    {
        if ($this->sections !== null) {
            return $this->sections;
        }

        $yearId = AcademicYear::query()
            ->where('school_id', $schoolId)
            ->where('is_current', true)
            ->value('id');

        if ($yearId === null) {
            return $this->sections = [];
        }

        $sections = ClassSection::query()
            ->join('school_classes', 'school_classes.id', '=', 'class_sections.school_class_id')
            ->where('school_classes.academic_year_id', $yearId)
            ->get(['class_sections.id', 'class_sections.name as section_name', 'school_classes.name as class_name']);

        $this->sections = [];

        foreach ($sections as $section) {
            $this->sections[$this->key($section->class_name, $section->section_name)] = $section->id;
        }

        return $this->sections;
    }

    /** Case and stray spaces should not decide whether a row imports. */
    private function key(string $class, string $section): string
    {
        return mb_strtolower(trim($class)).'|'.mb_strtolower(trim($section));
    }
}
