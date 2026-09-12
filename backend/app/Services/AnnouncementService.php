<?php

namespace App\Services;

use App\Enums\AnnouncementAudience;
use App\Enums\AnnouncementChannels;
use App\Enums\MessageChannel;
use App\Enums\MessageEvent;
use App\Enums\StudentStatus;
use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Exceptions\UnreachableAudienceException;
use App\Jobs\PublishAnnouncementJob;
use App\Models\Announcement;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\Student;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

/**
 * Publishing a notice to a school audience. The audience is resolved into
 * real people here; the actual fan-out runs on the queue so a whole-school
 * announcement does not hold up the request.
 */
class AnnouncementService
{
    /** How many recipients are turned into messages per batch. */
    private const int CHUNK = 200;

    public function __construct(private readonly NotificationService $notifications) {}

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Announcement::query()
            ->with(['school', 'publishedBy'])
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn (Builder $query) => $query->where('school_id', $actor->school_id),
                fn (Builder $query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn (Builder $query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            // A head of department manages their own department's notices and
            // nothing else, so the list must not show them the rest.
            ->when(
                $actor->role === UserRole::Hod,
                fn (Builder $query) => $query
                    ->where('audience_type', AnnouncementAudience::Department)
                    ->whereIn('audience_id', Department::query()
                        ->where('school_id', $actor->school_id)
                        ->where('hod_user_id', $actor->id)
                        ->pluck('id'))
            )
            ->when(
                $filters['audience_type'] ?? null,
                fn (Builder $query, $audience) => $query->where('audience_type', $audience)
            )
            ->when($filters['q'] ?? null, function (Builder $query, string $term) {
                $like = '%'.$term.'%';
                $query->where(fn (Builder $inner) => $inner->where('title', 'like', $like)->orWhere('body', 'like', $like));
            })
            ->when(
                filter_var($filters['active_only'] ?? false, FILTER_VALIDATE_BOOLEAN),
                fn (Builder $query) => $query->where(
                    fn (Builder $inner) => $inner->whereNull('expires_at')->orWhereDate('expires_at', '>=', now()->toDateString())
                )
            )
            ->latest('published_at')
            ->latest('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function publish(array $data, User $actor): Announcement
    {
        $schoolId = (int) $data['school_id'];
        $audience = AnnouncementAudience::from($data['audience_type']);
        $channels = AnnouncementChannels::from($data['channels']);
        $target = $audience->needsTarget() ? (int) $data['audience_id'] : null;

        $counts = $this->countRecipients($schoolId, $audience, $target, $channels);

        if ($counts['recipients'] === 0) {
            throw new UnreachableAudienceException(
                $this->unreachableReason($audience, $channels),
            );
        }

        $announcement = DB::transaction(function () use ($data, $schoolId, $audience, $channels, $target, $counts, $actor) {
            return Announcement::create([
                'school_id' => $schoolId,
                'title' => $data['title'],
                'body' => $data['body'],
                'audience_type' => $audience,
                'audience_id' => $target,
                'audience_label' => $this->audienceLabel($audience, $target),
                'channels' => $channels,
                'expires_at' => $data['expires_at'] ?? null,
                'published_by' => $actor->id,
                'published_at' => now(),
                'recipients_count' => $counts['recipients'],
                'sms_count' => $counts['sms'],
                'in_app_count' => $counts['in_app'],
            ]);
        });

        DB::afterCommit(fn () => PublishAnnouncementJob::dispatch($announcement->id, $actor->id));

        return $announcement->fresh(['school', 'publishedBy']);
    }

    /**
     * Turns the audience into messages. Runs from PublishAnnouncementJob, in
     * chunks, so a school with a thousand students is not one huge write.
     */
    public function fanOut(Announcement $announcement, ?User $actor): void
    {
        $announcement->loadMissing('school');
        $channels = $announcement->channels->messageChannels();
        $tokens = [
            'title' => $announcement->title,
            'body' => $announcement->body,
            'school_name' => $announcement->school?->name,
            'audience' => $announcement->audience_label,
        ];

        if ($announcement->channels->includesSms() && $announcement->audience_type->reachesGuardians()) {
            $this->studentsFor($announcement)->chunkById(self::CHUNK, function (Collection $students) use ($announcement, $tokens, $actor) {
                foreach ($students as $student) {
                    $this->notifications->notifyGuardian(
                        MessageEvent::AnnouncementPublished,
                        $student,
                        $tokens,
                        $actor,
                        channels: [MessageChannel::Sms],
                        announcement: $announcement,
                    );
                }
            });
        }

        if ($announcement->audience_type->reachesStaff()) {
            $this->usersFor($announcement)->chunkById(self::CHUNK, function (Collection $users) use ($announcement, $channels, $tokens, $actor) {
                foreach ($users as $user) {
                    $this->notifications->notifyUser(
                        MessageEvent::AnnouncementPublished,
                        $user,
                        $tokens,
                        $actor,
                        channels: $channels,
                        announcement: $announcement,
                    );
                }
            });
        }
    }

    /**
     * Takes the notice out of the in-app feed. Messages already sent stay in
     * the log - see the note on the model.
     */
    public function delete(Announcement $announcement): void
    {
        $announcement->delete();
    }

    /**
     * @return array{recipients: int, sms: int, in_app: int}
     */
    public function countRecipients(int $schoolId, AnnouncementAudience $audience, ?int $target, AnnouncementChannels $channels): array
    {
        $guardians = 0;
        $staff = 0;

        if ($channels->includesSms() && $audience->reachesGuardians()) {
            $guardians = $this->studentQuery($schoolId, $audience, $target)->whereNotNull('guardian_mobile')->count();
        }

        if ($audience->reachesStaff()) {
            $staff = $this->userQuery($schoolId, $audience, $target)->count();
        }

        $sms = $guardians + ($channels->includesSms() ? $staff : 0);
        $inApp = $channels->includesInApp() ? $staff : 0;

        return [
            'recipients' => $guardians + $staff,
            'sms' => $sms,
            'in_app' => $inApp,
        ];
    }

    public function audienceLabel(AnnouncementAudience $audience, ?int $target): string
    {
        return match ($audience) {
            AnnouncementAudience::ClassSection => $this->classSectionLabel($target),
            AnnouncementAudience::Department => Department::find($target)?->name ?? 'Department',
            default => $audience->label(),
        };
    }

    private function classSectionLabel(?int $target): string
    {
        $section = ClassSection::with('schoolClass')->find($target);

        return $section === null ? 'Class' : trim("{$section->schoolClass?->name} {$section->name}");
    }

    /**
     * @return Builder<Student>
     */
    private function studentsFor(Announcement $announcement): Builder
    {
        // No whereNotNull here on purpose: a guardian with no number on record
        // still gets a "skipped" row, so an admin can see who was missed.
        return $this->studentQuery(
            $announcement->school_id,
            $announcement->audience_type,
            $announcement->audience_id,
        );
    }

    /**
     * @return Builder<User>
     */
    private function usersFor(Announcement $announcement): Builder
    {
        return $this->userQuery(
            $announcement->school_id,
            $announcement->audience_type,
            $announcement->audience_id,
        );
    }

    /**
     * @return Builder<Student>
     */
    private function studentQuery(int $schoolId, AnnouncementAudience $audience, ?int $target): Builder
    {
        return Student::query()
            ->where('school_id', $schoolId)
            ->where('status', StudentStatus::Active)
            ->when(
                $audience === AnnouncementAudience::ClassSection,
                fn (Builder $query) => $query->where('class_section_id', $target)
            );
    }

    /**
     * Only active accounts, and never the Super Admin platform accounts -
     * they belong to no school.
     *
     * @return Builder<User>
     */
    private function userQuery(int $schoolId, AnnouncementAudience $audience, ?int $target): Builder
    {
        return User::query()
            ->where('school_id', $schoolId)
            ->where('status', UserStatus::Active)
            ->when(
                $audience === AnnouncementAudience::Teachers,
                fn (Builder $query) => $query->whereIn('role', [UserRole::Teacher, UserRole::Hod])
            )
            ->when(
                $audience === AnnouncementAudience::Department,
                fn (Builder $query) => $query->whereHas(
                    'staffProfile',
                    fn (Builder $profile) => $profile->where('department_id', $target)
                )
            );
    }

    private function unreachableReason(AnnouncementAudience $audience, AnnouncementChannels $channels): string
    {
        if ($channels === AnnouncementChannels::InAppOnly && ! $audience->reachesStaff()) {
            return 'Guardians have no app login, so this audience can only be reached by SMS.';
        }

        return 'Nobody in this audience can be reached right now.';
    }
}
