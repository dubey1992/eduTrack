<?php

namespace App\Enums;

enum UserRole: string
{
    case SuperAdmin = 'SUPER_ADMIN';
    // Attached to a parent school: reads every branch in its group, and
    // writes into whichever branch it names. Not a platform role - schools
    // and payments stay SUPER_ADMIN. See docs/branches.md.
    case GroupAdmin = 'GROUP_ADMIN';
    // Attached to any one school. Where that school is part of a group, the
    // same group reach as a Group Admin - the head office looks down at its
    // branches and a branch looks up and across at its sisters. Where it is
    // standalone, which is most schools, exactly one school as always.
    case SchoolAdmin = 'SCHOOL_ADMIN';
    case Hod = 'HOD';
    case Teacher = 'TEACHER';
    case Staff = 'STAFF';
    case TransportManager = 'TRANSPORT_MANAGER';

    /**
     * Administers schools' own affairs - their own school, and every branch
     * in its group where there is one.
     *
     * Says nothing about *which* schools: that is SchoolScope's question, and
     * asking it here instead is how the two would drift apart.
     *
     * Deliberately not "is an admin": onboarding a school and recording the
     * payments it makes are platform actions and stay SUPER_ADMIN.
     */
    public function administersSchool(): bool
    {
        return $this === self::SchoolAdmin || $this === self::GroupAdmin;
    }
}
