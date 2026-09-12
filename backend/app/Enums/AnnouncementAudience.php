<?php

namespace App\Enums;

/**
 * The prototype's audience picker. Everything except Department reaches
 * guardians, staff, or both; Department reaches that department's staff.
 */
enum AnnouncementAudience: string
{
    case AllSchool = 'all_school';
    case Teachers = 'teachers';
    case Parents = 'parents';
    case ClassSection = 'class_section';
    case Department = 'department';

    public function label(): string
    {
        return match ($this) {
            self::AllSchool => 'All School',
            self::Teachers => 'Teachers',
            self::Parents => 'Parents',
            self::ClassSection => 'A class section',
            self::Department => 'A department',
        };
    }

    /**
     * Audiences that name a specific class section or department.
     */
    public function needsTarget(): bool
    {
        return $this === self::ClassSection || $this === self::Department;
    }

    /**
     * Guardians have no login, so an audience made only of them can never be
     * reached in-app.
     */
    public function reachesGuardians(): bool
    {
        return in_array($this, [self::AllSchool, self::Parents, self::ClassSection], true);
    }

    public function reachesStaff(): bool
    {
        return in_array($this, [self::AllSchool, self::Teachers, self::Department], true);
    }
}
