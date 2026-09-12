<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Message;
use App\Models\User;

/**
 * The message log holds guardians' phone numbers and what was said to them,
 * so only the admins who run the school may read it. Everyone can read their
 * own inbox, which is a different thing and not gated here.
 */
class MessagePolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function view(User $actor, Message $message): bool
    {
        return $this->manages($actor, $message->school_id);
    }

    public function retry(User $actor, Message $message): bool
    {
        return $this->manages($actor, $message->school_id);
    }

    /**
     * Reading or changing a school's templates and alert switches.
     */
    public function configure(User $actor, ?int $schoolId = null): bool
    {
        return $this->manages($actor, $schoolId);
    }

    private function manages(User $actor, ?int $schoolId): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin
            && $schoolId !== null
            && $actor->school_id === $schoolId;
    }
}
