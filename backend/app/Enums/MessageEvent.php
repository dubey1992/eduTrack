<?php

namespace App\Enums;

/**
 * Every automatic message the product can send. Each case owns its default
 * wording, the tokens that wording may use, the log category and the channels
 * it goes out on. A school can override the wording (message_templates) but
 * not the token list, so a reworded template can never reference data the
 * sender does not have.
 */
enum MessageEvent: string
{
    case AttendancePresent = 'attendance.present';
    case AttendanceAbsent = 'attendance.absent';
    case TransportBoarded = 'transport.boarded';
    case TransportDropped = 'transport.dropped';
    case TransportAbsent = 'transport.absent';
    case LeaveApproved = 'leave.approved';
    case LeaveRejected = 'leave.rejected';
    case AnnouncementPublished = 'announcement.published';

    public function label(): string
    {
        return match ($this) {
            self::AttendancePresent => 'Marked present',
            self::AttendanceAbsent => 'Marked absent',
            self::TransportBoarded => 'Boarded the bus',
            self::TransportDropped => 'Dropped off',
            self::TransportAbsent => 'Did not board',
            self::LeaveApproved => 'Leave approved',
            self::LeaveRejected => 'Leave rejected',
            self::AnnouncementPublished => 'Announcement',
        };
    }

    public function category(): MessageCategory
    {
        return match ($this) {
            self::AttendancePresent, self::AttendanceAbsent => MessageCategory::Attendance,
            self::TransportBoarded, self::TransportDropped, self::TransportAbsent => MessageCategory::Transport,
            self::LeaveApproved, self::LeaveRejected => MessageCategory::Leave,
            self::AnnouncementPublished => MessageCategory::Announcement,
        };
    }

    /**
     * Guardians have no login, so student alerts are SMS only. Staff alerts
     * also land in the in-app inbox.
     *
     * @return array<int, MessageChannel>
     */
    public function channels(): array
    {
        return match ($this->category()) {
            MessageCategory::Leave => [MessageChannel::InApp, MessageChannel::Sms],
            // An announcement picks its own channels when it is published.
            MessageCategory::Announcement => [MessageChannel::InApp, MessageChannel::Sms],
            default => [MessageChannel::Sms],
        };
    }

    public function defaultBody(): string
    {
        return match ($this) {
            self::AttendancePresent => '{student_name} was marked PRESENT on {date}. - {school_name}',
            self::AttendanceAbsent => '{student_name} was marked ABSENT on {date}. Please contact the school office if this is unexpected. - {school_name}',
            self::TransportBoarded => '{student_name} boarded {vehicle_name} at {stop_name} at {time}. - {school_name}',
            self::TransportDropped => '{student_name} was dropped off at {stop_name} at {time}. - {school_name}',
            self::TransportAbsent => '{student_name} did not board {vehicle_name} for the {direction} trip today. - {school_name}',
            self::LeaveApproved => 'Your {leave_type} leave from {start_date} to {end_date} has been approved.',
            self::LeaveRejected => 'Your {leave_type} leave from {start_date} to {end_date} was not approved.',
            self::AnnouncementPublished => '{school_name}: {title} - {body}',
        };
    }

    /**
     * @return array<int, string>
     */
    public function tokens(): array
    {
        return match ($this) {
            self::AttendancePresent, self::AttendanceAbsent => [
                'student_name', 'class_name', 'date', 'school_name', 'guardian_name',
            ],
            self::TransportBoarded, self::TransportDropped => [
                'student_name', 'stop_name', 'vehicle_name', 'route_name', 'time', 'date', 'school_name', 'guardian_name',
            ],
            self::TransportAbsent => [
                'student_name', 'stop_name', 'vehicle_name', 'route_name', 'direction', 'date', 'school_name', 'guardian_name',
            ],
            self::LeaveApproved, self::LeaveRejected => [
                'staff_name', 'leave_type', 'start_date', 'end_date', 'days', 'remarks', 'school_name',
            ],
            self::AnnouncementPublished => ['title', 'body', 'school_name', 'audience'],
        };
    }
}
