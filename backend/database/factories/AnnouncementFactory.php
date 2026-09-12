<?php

namespace Database\Factories;

use App\Enums\AnnouncementAudience;
use App\Enums\AnnouncementChannels;
use App\Models\Announcement;
use App\Models\Department;
use App\Models\School;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Announcement>
 */
class AnnouncementFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'title' => 'Parent meeting',
            'body' => 'Parent meeting scheduled Friday at 3 PM.',
            'audience_type' => AnnouncementAudience::AllSchool,
            'audience_id' => null,
            'audience_label' => 'All School',
            'channels' => AnnouncementChannels::SmsAndInApp,
            'expires_at' => null,
            'published_by' => null,
            'published_at' => now(),
            'recipients_count' => 0,
            'sms_count' => 0,
            'in_app_count' => 0,
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function publishedBy(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $user->school_id,
            'published_by' => $user->id,
        ]);
    }

    public function forDepartment(Department $department): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $department->school_id,
            'audience_type' => AnnouncementAudience::Department,
            'audience_id' => $department->id,
            'audience_label' => $department->name,
        ]);
    }

    public function channels(AnnouncementChannels $channels): static
    {
        return $this->state(fn (array $attributes) => ['channels' => $channels]);
    }

    public function expiringOn(string $date): static
    {
        return $this->state(fn (array $attributes) => ['expires_at' => $date]);
    }
}
