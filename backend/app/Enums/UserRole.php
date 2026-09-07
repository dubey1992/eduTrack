<?php

namespace App\Enums;

enum UserRole: string
{
    case SuperAdmin = 'SUPER_ADMIN';
    case SchoolAdmin = 'SCHOOL_ADMIN';
    case Hod = 'HOD';
    case Teacher = 'TEACHER';
    case Staff = 'STAFF';
    case TransportManager = 'TRANSPORT_MANAGER';
}
