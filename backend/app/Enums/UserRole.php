<?php

namespace App\Enums;

enum UserRole: string
{
    case SuperAdmin = 'SUPER_ADMIN';
    // Attached to a parent school: reads every branch in its group, and
    // writes into whichever branch it names. Not a platform role - schools
    // and payments stay SUPER_ADMIN. See docs/branches.md.
    case GroupAdmin = 'GROUP_ADMIN';
    case SchoolAdmin = 'SCHOOL_ADMIN';
    case Hod = 'HOD';
    case Teacher = 'TEACHER';
    case Staff = 'STAFF';
    case TransportManager = 'TRANSPORT_MANAGER';

    /**
     * Administers schools' own affairs - one school for a School Admin, every
     * branch in the group for a Group Admin.
     *
     * Deliberately not "is an admin": onboarding a school and recording the
     * payments it makes are platform actions and stay SUPER_ADMIN.
     */
    public function administersSchool(): bool
    {
        return $this === self::SchoolAdmin || $this === self::GroupAdmin;
    }
}
