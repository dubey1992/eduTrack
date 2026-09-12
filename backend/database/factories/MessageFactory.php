<?php

namespace Database\Factories;

use App\Enums\MessageChannel;
use App\Enums\MessageEvent;
use App\Enums\MessageStatus;
use App\Models\Message;
use App\Models\School;
use App\Models\Student;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Message>
 */
class MessageFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $event = MessageEvent::AttendanceAbsent;

        return [
            'school_id' => School::factory(),
            'event' => $event,
            'category' => $event->category(),
            'channel' => MessageChannel::Sms,
            'recipient_name' => fake()->name(),
            'recipient_mobile' => '+91 98765'.fake()->numerify('#####'),
            'user_id' => null,
            'student_id' => null,
            'student_name' => fake()->name(),
            'body' => 'Arjun Kumar was marked ABSENT today.',
            'status' => MessageStatus::Sent,
            'provider' => 'log',
            'provider_message_id' => 'demo-'.fake()->uuid(),
            'failure_reason' => null,
            'created_by' => null,
            'sent_at' => now(),
            'read_at' => null,
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function forEvent(MessageEvent $event): static
    {
        return $this->state(fn (array $attributes) => [
            'event' => $event,
            'category' => $event->category(),
        ]);
    }

    public function status(MessageStatus $status): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => $status,
            'sent_at' => $status === MessageStatus::Sent ? now() : null,
            'failure_reason' => $status === MessageStatus::Failed ? 'The gateway rejected the number.' : null,
        ]);
    }

    public function forStudent(Student $student): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $student->school_id,
            'student_id' => $student->id,
            'student_name' => $student->name,
            'recipient_name' => $student->guardian_name,
            'recipient_mobile' => $student->guardian_mobile,
        ]);
    }

    /**
     * An in-app message sitting in one user's inbox.
     */
    public function inboxFor(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $user->school_id,
            'channel' => MessageChannel::InApp,
            'event' => MessageEvent::LeaveApproved,
            'category' => MessageEvent::LeaveApproved->category(),
            'user_id' => $user->id,
            'recipient_name' => $user->name,
            'recipient_mobile' => null,
            'student_id' => null,
            'student_name' => null,
            'provider' => null,
        ]);
    }
}
