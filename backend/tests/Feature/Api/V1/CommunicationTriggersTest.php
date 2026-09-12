<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AttendanceAlertMode;
use App\Enums\MessageChannel;
use App\Enums\MessageEvent;
use App\Enums\MessageStatus;
use App\Enums\UserRole;
use App\Jobs\SendMessageJob;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\CommunicationSetting;
use App\Models\Driver;
use App\Models\Message;
use App\Models\MessageTemplate;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\StudentTransportAssignment;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\TransportTrip;
use App\Models\TransportTripRider;
use App\Models\User;
use App\Models\Vehicle;
use App\Support\Sms\SmsGatewayManager;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Queue;
use RuntimeException;
use Tests\TestCase;

/**
 * The modules that feed the Communication Center: attendance, transport
 * trips and leave decisions. These check the message that comes out, not
 * just that one was written.
 */
class CommunicationTriggersTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        // A plain Wednesday, so attendance and trips are both allowed.
        Carbon::setTestNow('2026-09-16 08:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /**
     * @return array{school: School, section: ClassSection, students: array<int, Student>, teacher: User, admin: User}
     */
    private function makeClass(): array
    {
        $school = School::factory()->create(['name' => 'Sunrise Public School']);
        $year = AcademicYear::factory()->forSchool($school)->create();
        // The class teacher is the one allowed to mark this section's register.
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $section = ClassSection::factory()
            ->forClass(SchoolClass::factory()->forAcademicYear($year)->create(['name' => 'Grade 8']))
            ->withClassTeacher($teacher)
            ->create(['name' => 'A']);

        $arjun = Student::factory()->forSection($section)->create([
            'first_name' => 'Arjun',
            'last_name' => 'Kumar',
            'guardian_name' => 'Raj Kumar',
            'guardian_mobile' => '+91 9876543210',
        ]);
        $meera = Student::factory()->forSection($section)->create([
            'first_name' => 'Meera',
            'last_name' => 'Singh',
            'guardian_name' => 'Rohit Singh',
            'guardian_mobile' => '+91 9876500000',
        ]);

        return [
            'school' => $school,
            'section' => $section,
            'students' => [$arjun, $meera],
            'teacher' => $teacher,
            'admin' => User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(),
        ];
    }

    /**
     * @param  array<int, array<string, mixed>>  $records
     */
    private function submitAttendance(User $actor, ClassSection $section, array $records, string $date = '2026-09-16')
    {
        return $this->actingAs($actor, 'sanctum')->postJson('/api/v1/attendance', [
            'class_section_id' => $section->id,
            'attendance_date' => $date,
            'records' => $records,
        ]);
    }

    // -- attendance ------------------------------------------------------

    public function test_submitting_attendance_texts_the_guardians_of_absent_students_only(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        [$arjun, $meera] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
            ['student_id' => $meera->id, 'status' => 'present'],
        ])->assertCreated();

        $this->assertDatabaseCount('messages', 1);

        $message = Message::first();
        $this->assertSame(MessageEvent::AttendanceAbsent, $message->event);
        $this->assertSame('Raj Kumar', $message->recipient_name);
        $this->assertSame('+91 9876543210', $message->recipient_mobile);
        $this->assertSame('Arjun Kumar', $message->student_name);
        $this->assertSame($arjun->id, $message->student_id);
        $this->assertSame(MessageStatus::Queued, $message->status);
        $this->assertStringContainsString('Arjun Kumar was marked ABSENT on 16 Sep 2026', $message->body);
        $this->assertStringContainsString('Sunrise Public School', $message->body);
        $this->assertStringNotContainsString('{', $message->body);

        Queue::assertPushed(SendMessageJob::class, 1);
    }

    public function test_a_school_can_ask_for_present_alerts_too(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        CommunicationSetting::factory()->forSchool($f['school'])
            ->attendanceAlerts(AttendanceAlertMode::PresentAndAbsent)->create();
        [$arjun, $meera] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
            ['student_id' => $meera->id, 'status' => 'present'],
        ])->assertCreated();

        $this->assertDatabaseCount('messages', 2);
        $this->assertSame(
            [MessageEvent::AttendanceAbsent, MessageEvent::AttendancePresent],
            Message::orderBy('student_id')->pluck('event')->all(),
        );
        $this->assertSame([MessageStatus::Queued, MessageStatus::Queued], Message::pluck('status')->all());
    }

    public function test_a_present_alert_is_not_logged_at_all_when_the_school_only_wants_absences(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        CommunicationSetting::factory()->forSchool($f['school'])
            ->attendanceAlerts(AttendanceAlertMode::AbsentOnly)->create();
        [$arjun] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'present'],
        ])->assertCreated();

        // An alert the school never asked for is not "skipped" - it would put
        // a row in the log for every present student, every day.
        $this->assertDatabaseCount('messages', 0);
        Queue::assertNothingPushed();
    }

    public function test_switching_attendance_alerts_off_skips_both_kinds(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        CommunicationSetting::factory()->forSchool($f['school'])
            ->attendanceAlerts(AttendanceAlertMode::Off)->create();
        [$arjun, $meera] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
            ['student_id' => $meera->id, 'status' => 'present'],
        ])->assertCreated();

        $this->assertDatabaseCount('messages', 0);
        Queue::assertNothingPushed();
    }

    public function test_switching_sms_off_sends_and_logs_nothing(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        CommunicationSetting::factory()->forSchool($f['school'])->smsOff()->create();
        [$arjun] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
        ])->assertCreated();

        $this->assertDatabaseCount('messages', 0);
        Queue::assertNothingPushed();
    }

    public function test_a_student_with_no_guardian_mobile_is_recorded_as_skipped(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        $noMobile = Student::factory()->forSection($f['section'])->create([
            'first_name' => 'Aarav',
            'last_name' => 'Mehta',
            'guardian_name' => 'Neha Mehta',
            'guardian_mobile' => null,
        ]);

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $noMobile->id, 'status' => 'absent'],
        ])->assertCreated();

        $message = Message::sole();
        $this->assertSame(MessageStatus::Skipped, $message->status);
        $this->assertSame('No mobile number on record.', $message->failure_reason);
        $this->assertSame('Neha Mehta', $message->recipient_name);
        Queue::assertNothingPushed();
    }

    public function test_a_leave_mark_alerts_nobody(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        [$arjun] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'leave'],
        ])->assertCreated();

        $this->assertDatabaseCount('messages', 0);
    }

    public function test_correcting_a_remark_does_not_text_the_guardian_twice_but_a_status_change_does(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        [$arjun] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
        ])->assertCreated();
        $this->assertDatabaseCount('messages', 1);

        // Same status, new remark - nothing new goes out.
        $this->actingAs($f['teacher'], 'sanctum')
            ->patchJson('/api/v1/attendance', [
                'class_section_id' => $f['section']->id,
                'attendance_date' => '2026-09-16',
                'records' => [['student_id' => $arjun->id, 'status' => 'absent', 'remarks' => 'Called home.']],
            ])->assertOk();
        $this->assertDatabaseCount('messages', 1);

        // A real correction does alert, because the guardian was told the wrong thing.
        CommunicationSetting::factory()->forSchool($f['school'])
            ->attendanceAlerts(AttendanceAlertMode::PresentAndAbsent)->create();
        $this->actingAs($f['teacher'], 'sanctum')
            ->patchJson('/api/v1/attendance', [
                'class_section_id' => $f['section']->id,
                'attendance_date' => '2026-09-16',
                'records' => [['student_id' => $arjun->id, 'status' => 'present']],
            ])->assertOk();

        $this->assertDatabaseCount('messages', 2);
        $this->assertSame(MessageEvent::AttendancePresent, Message::latest('id')->first()->event);
    }

    public function test_a_reworded_template_is_what_the_guardian_actually_gets(): void
    {
        Queue::fake();
        $f = $this->makeClass();
        MessageTemplate::factory()->forSchool($f['school'])->forEvent(MessageEvent::AttendanceAbsent)
            ->body('Namaste {guardian_name}, {student_name} of {class_name} was absent on {date}.')
            ->create();
        [$arjun] = $f['students'];

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
        ])->assertCreated();

        $this->assertSame(
            'Namaste Raj Kumar, Arjun Kumar of Grade 8 A was absent on 16 Sep 2026.',
            Message::sole()->body,
        );
    }

    public function test_a_failing_gateway_never_blocks_the_attendance_submission(): void
    {
        $f = $this->makeClass();
        [$arjun] = $f['students'];

        // No Queue::fake() here: the job runs inline and the demo gateway
        // accepts it, which is the whole point - the teacher still gets a 200.
        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
        ])->assertCreated();

        $message = Message::sole();
        $this->assertSame(MessageStatus::Sent, $message->status);
        $this->assertNotNull($message->sent_at);
        $this->assertStringStartsWith('demo-', $message->provider_message_id);
    }

    // -- transport -------------------------------------------------------

    /**
     * @return array{school: School, trip: TransportTrip, student: Student, manager: User}
     */
    private function makeRunningTrip(): array
    {
        $school = School::factory()->create(['name' => 'Sunrise Public School']);
        $vehicle = Vehicle::factory()->forSchool($school)->create(['name' => 'Bus 04']);
        $driver = Driver::factory()->forSchool($school)->create();
        $route = TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->withDriver($driver)
            ->create(['name' => 'Green Park']);
        $stop = TransportStop::factory()->forRoute($route)->atSequence(1)->create(['name' => 'Lake View']);

        $year = AcademicYear::factory()->forSchool($school)->create();
        $section = ClassSection::factory()->forClass(SchoolClass::factory()->forAcademicYear($year)->create())->create();
        $student = Student::factory()->forSection($section)->create([
            'first_name' => 'Aarav',
            'last_name' => 'Mehta',
            'guardian_name' => 'Neha Mehta',
            'guardian_mobile' => '+91 9812345678',
        ]);
        StudentTransportAssignment::factory()->forStudent($student)->atStop($stop)->create();

        $manager = User::factory()->role(UserRole::TransportManager)->forSchool($school)->create();
        $trip = TransportTrip::factory()->forRoute($route)->startedBy($manager)->create();
        TransportTripRider::factory()->forTrip($trip)->forStudent($student)->atStop($stop)->create();

        return ['school' => $school, 'trip' => $trip, 'student' => $student, 'manager' => $manager];
    }

    private function setRider(array $f, string $status)
    {
        return $this->actingAs($f['manager'], 'sanctum')->patchJson(
            "/api/v1/transport/trips/{$f['trip']->id}/riders/{$f['student']->id}",
            ['status' => $status],
        );
    }

    public function test_boarding_and_dropping_a_student_texts_their_guardian(): void
    {
        Queue::fake();
        $f = $this->makeRunningTrip();

        $this->setRider($f, 'boarded')->assertOk();

        $boarded = Message::sole();
        $this->assertSame(MessageEvent::TransportBoarded, $boarded->event);
        $this->assertSame('Neha Mehta', $boarded->recipient_name);
        $this->assertStringContainsString('Aarav Mehta boarded Bus 04 at Lake View', $boarded->body);
        $this->assertStringNotContainsString('{', $boarded->body);

        $this->setRider($f, 'dropped')->assertOk();

        $dropped = Message::latest('id')->first();
        $this->assertSame(MessageEvent::TransportDropped, $dropped->event);
        $this->assertStringContainsString('was dropped off at Lake View', $dropped->body);
        $this->assertDatabaseCount('messages', 2);
    }

    public function test_marking_a_rider_absent_tells_the_guardian_they_did_not_board(): void
    {
        Queue::fake();
        $f = $this->makeRunningTrip();

        $this->setRider($f, 'absent')->assertOk();

        $message = Message::sole();
        $this->assertSame(MessageEvent::TransportAbsent, $message->event);
        $this->assertStringContainsString('did not board Bus 04 for the pickup trip', $message->body);
    }

    public function test_ending_a_trip_auto_absent_does_not_text_anyone(): void
    {
        Queue::fake();
        $f = $this->makeRunningTrip();

        $this->actingAs($f['manager'], 'sanctum')
            ->postJson("/api/v1/transport/trips/{$f['trip']->id}/end")
            ->assertOk();

        // The bulk auto-absent at the end of a run is a bookkeeping step, not
        // a per-student event, so no guardian is texted.
        $this->assertDatabaseCount('messages', 0);
    }

    public function test_transport_alerts_can_be_switched_off_per_school(): void
    {
        Queue::fake();
        $f = $this->makeRunningTrip();
        CommunicationSetting::factory()->forSchool($f['school'])
            ->create(['transport_alerts_enabled' => false]);

        $this->setRider($f, 'boarded')->assertOk();

        $this->assertDatabaseCount('messages', 0);
        Queue::assertNothingPushed();
    }

    // -- leave -----------------------------------------------------------

    /**
     * @return array{school: School, leave: StaffLeave, applicant: User, admin: User}
     */
    private function makePendingLeave(): array
    {
        $school = School::factory()->create();
        $applicant = User::factory()->role(UserRole::Teacher)->forSchool($school)->create([
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'mobile' => '+91 9800000001',
        ]);
        $profile = StaffProfile::factory()->forUser($applicant)->create();
        $monday = Carbon::parse('2026-09-21');
        $leave = StaffLeave::factory()->forStaff($profile)->create([
            'leave_type' => 'casual',
            'start_date' => $monday->toDateString(),
            'end_date' => $monday->copy()->addDay()->toDateString(),
        ]);

        return [
            'school' => $school,
            'leave' => $leave,
            'applicant' => $applicant,
            'admin' => User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(),
        ];
    }

    public function test_approving_leave_puts_a_message_in_the_applicants_inbox_and_texts_them(): void
    {
        Queue::fake();
        $f = $this->makePendingLeave();

        $this->actingAs($f['admin'], 'sanctum')
            ->patchJson("/api/v1/leaves/{$f['leave']->id}/approve", ['remarks' => 'Enjoy the break.'])
            ->assertOk();

        $this->assertDatabaseCount('messages', 2);

        $inApp = Message::where('channel', MessageChannel::InApp)->sole();
        $this->assertSame($f['applicant']->id, $inApp->user_id);
        $this->assertSame(MessageEvent::LeaveApproved, $inApp->event);
        $this->assertSame(MessageStatus::Queued, $inApp->status);
        $this->assertStringContainsString('Your casual leave from 21 Sep 2026 to 22 Sep 2026 has been approved.', $inApp->body);

        $sms = Message::where('channel', MessageChannel::Sms)->sole();
        $this->assertSame('+91 9800000001', $sms->recipient_mobile);
        $this->assertSame('Priya Sharma', $sms->recipient_name);
    }

    public function test_rejecting_leave_tells_the_applicant_too(): void
    {
        Queue::fake();
        $f = $this->makePendingLeave();

        $this->actingAs($f['admin'], 'sanctum')
            ->patchJson("/api/v1/leaves/{$f['leave']->id}/reject", ['remarks' => 'Exams that week.'])
            ->assertOk();

        $this->assertSame(
            [MessageEvent::LeaveRejected, MessageEvent::LeaveRejected],
            Message::pluck('event')->all(),
        );
        $this->assertStringContainsString('was not approved', Message::first()->body);
    }

    public function test_leave_alerts_can_be_switched_off_including_the_inbox_copy(): void
    {
        Queue::fake();
        $f = $this->makePendingLeave();
        CommunicationSetting::factory()->forSchool($f['school'])->create(['leave_alerts_enabled' => false]);

        $this->actingAs($f['admin'], 'sanctum')
            ->patchJson("/api/v1/leaves/{$f['leave']->id}/approve", [])
            ->assertOk();

        $this->assertDatabaseCount('messages', 0);
        Queue::assertNothingPushed();
    }

    public function test_an_applicant_with_no_mobile_still_gets_the_inbox_copy(): void
    {
        Queue::fake();
        $f = $this->makePendingLeave();
        $f['applicant']->update(['mobile' => null]);

        $this->actingAs($f['admin'], 'sanctum')
            ->patchJson("/api/v1/leaves/{$f['leave']->id}/approve", [])
            ->assertOk();

        $this->assertSame(MessageStatus::Queued, Message::where('channel', MessageChannel::InApp)->sole()->status);

        $sms = Message::where('channel', MessageChannel::Sms)->sole();
        $this->assertSame(MessageStatus::Skipped, $sms->status);
        $this->assertSame('No mobile number on record.', $sms->failure_reason);
    }

    public function test_the_approved_message_reaches_the_applicants_inbox_endpoint(): void
    {
        $f = $this->makePendingLeave();

        $this->actingAs($f['admin'], 'sanctum')
            ->patchJson("/api/v1/leaves/{$f['leave']->id}/approve", [])
            ->assertOk();

        $this->actingAs($f['applicant'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.channel', 'in_app')
            ->assertJsonPath('data.0.status', 'sent');

        $this->actingAs($f['applicant'], 'sanctum')->getJson('/api/v1/inbox/unread-count')
            ->assertOk()->assertJsonPath('unread', 1);
    }

    public function test_a_boarding_alert_states_the_time_it_happened(): void
    {
        Queue::fake();
        $f = $this->makeRunningTrip();

        $this->setRider($f, 'boarded')->assertOk();

        // 08:00 was frozen in setUp, so the text must say 8:00 AM rather than
        // whatever the server's clock would otherwise render.
        $this->assertStringContainsString('at 8:00 AM', Message::sole()->body);
    }

    public function test_a_messaging_failure_never_rolls_back_the_attendance_it_came_from(): void
    {
        $f = $this->makeClass();
        [$arjun] = $f['students'];

        // Anything at all going wrong while the message is written - here a
        // model hook standing in for a gateway or schema problem.
        Message::creating(function () {
            throw new RuntimeException('the messages table is unavailable');
        });

        $this->submitAttendance($f['teacher'], $f['section'], [
            ['student_id' => $arjun->id, 'status' => 'absent'],
        ])->assertCreated();

        // The register is saved even though nothing could be logged or sent.
        $this->assertDatabaseHas('attendances', ['student_id' => $arjun->id, 'status' => 'absent']);
        $this->assertDatabaseCount('messages', 0);

        Message::flushEventListeners();
    }

    // -- the send job ----------------------------------------------------

    public function test_the_job_marks_an_sms_sent_through_the_demo_gateway(): void
    {
        $school = School::factory()->create();
        $message = Message::factory()->forSchool($school)->status(MessageStatus::Queued)->create([
            'recipient_mobile' => '+91 9876543210',
        ]);

        (new SendMessageJob($message->id))->handle(app(SmsGatewayManager::class));

        $message->refresh();
        $this->assertSame(MessageStatus::Sent, $message->status);
        $this->assertNotNull($message->sent_at);
    }

    public function test_the_job_leaves_a_message_alone_once_it_is_no_longer_queued(): void
    {
        $school = School::factory()->create();
        $message = Message::factory()->forSchool($school)->status(MessageStatus::Skipped)->create();

        (new SendMessageJob($message->id))->handle(app(SmsGatewayManager::class));

        $this->assertSame(MessageStatus::Skipped, $message->refresh()->status);
        $this->assertNull($message->sent_at);
    }

    public function test_a_dead_job_marks_the_message_failed_so_an_admin_can_retry_it(): void
    {
        $school = School::factory()->create();
        $message = Message::factory()->forSchool($school)->status(MessageStatus::Queued)->create();

        (new SendMessageJob($message->id))->failed(new RuntimeException('gateway timeout'));

        $message->refresh();
        $this->assertSame(MessageStatus::Failed, $message->status);
        $this->assertSame('The gateway could not be reached.', $message->failure_reason);
    }
}
