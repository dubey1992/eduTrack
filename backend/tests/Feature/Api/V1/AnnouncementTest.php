<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AnnouncementAudience;
use App\Enums\AnnouncementChannels;
use App\Enums\MessageCategory;
use App\Enums\MessageChannel;
use App\Enums\MessageStatus;
use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\Announcement;
use App\Models\ClassSection;
use App\Models\CommunicationSetting;
use App\Models\Department;
use App\Models\Message;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Publishing a notice to a school audience, and the fan-out it produces.
 */
class AnnouncementTest extends TestCase
{
    use RefreshDatabase;

    private const string ANNOUNCEMENTS = '/api/v1/announcements';

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-09-16 09:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /**
     * A school with two guardians reachable by SMS, one without a number, a
     * teacher, a maths HOD, a plain staff member and a science HOD.
     *
     * @return array<string, mixed>
     */
    private function makeSchool(): array
    {
        $school = School::factory()->create(['name' => 'Sunrise Public School']);
        $year = AcademicYear::factory()->forSchool($school)->create();
        $section = ClassSection::factory()
            ->forClass(SchoolClass::factory()->forAcademicYear($year)->create(['name' => 'Grade 8']))
            ->create(['name' => 'A']);
        $otherSection = ClassSection::factory()
            ->forClass(SchoolClass::factory()->forAcademicYear($year)->create(['name' => 'Grade 9']))
            ->create(['name' => 'B']);

        $arjun = Student::factory()->forSection($section)->create([
            'first_name' => 'Arjun',
            'last_name' => 'Kumar',
            'guardian_name' => 'Raj Kumar',
            'guardian_mobile' => '+91 9876543210',
        ]);
        $meera = Student::factory()->forSection($otherSection)->create([
            'guardian_name' => 'Rohit Singh',
            'guardian_mobile' => '+91 9876500000',
        ]);
        $noMobile = Student::factory()->forSection($section)->create([
            'guardian_name' => 'Anita Rao',
            'guardian_mobile' => null,
        ]);
        Student::factory()->forSection($section)->inactive()->create(['guardian_mobile' => '+91 9000000000']);

        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create(['mobile' => '+91 9811111111']);
        $mathsHod = User::factory()->role(UserRole::Hod)->forSchool($school)->create(['mobile' => '+91 9822222222']);
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create(['mobile' => null]);

        $maths = Department::factory()->forSchool($school)->create(['name' => 'Mathematics', 'hod_user_id' => $mathsHod->id]);
        $science = Department::factory()->forSchool($school)->create(['name' => 'Science']);
        StaffProfile::factory()->forUser($mathsHod)->create(['department_id' => $maths->id]);
        StaffProfile::factory()->forUser($teacher)->create(['department_id' => $maths->id]);
        StaffProfile::factory()->forUser($staff)->create(['department_id' => $science->id]);

        return [
            'school' => $school,
            'section' => $section,
            'students' => [$arjun, $meera, $noMobile],
            'admin' => $admin,
            'teacher' => $teacher,
            'mathsHod' => $mathsHod,
            'staff' => $staff,
            'maths' => $maths,
            'science' => $science,
            'superAdmin' => User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]),
        ];
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function publish(User $actor, array $overrides = [])
    {
        return $this->actingAs($actor, 'sanctum')->postJson(self::ANNOUNCEMENTS, [
            'title' => 'Parent meeting',
            'body' => 'Parent meeting scheduled Friday at 3 PM.',
            'audience_type' => 'all_school',
            'channels' => 'sms_in_app',
            ...$overrides,
        ]);
    }

    // -- publishing ------------------------------------------------------

    public function test_an_admin_announces_to_the_whole_school_and_it_fans_out(): void
    {
        $f = $this->makeSchool();

        $response = $this->publish($f['admin']);

        $response->assertCreated()
            ->assertJsonPath('title', 'Parent meeting')
            ->assertJsonPath('audience_type', 'all_school')
            ->assertJsonPath('audience_label', 'All School')
            ->assertJsonPath('channels_label', 'SMS + In-app')
            ->assertJsonPath('published_by_name', $f['admin']->name)
            // 2 guardians with a number + 4 staff accounts.
            ->assertJsonPath('recipients_count', 6);

        // Guardians get SMS only; staff get both. The guardian with no number
        // and the staff member with no mobile are recorded as skipped rather
        // than dropped, so an admin can see who was missed.
        $this->assertSame(4, Message::where('channel', MessageChannel::InApp)->count());
        $this->assertSame(7, Message::where('channel', MessageChannel::Sms)->count());
        $this->assertSame(2, Message::where('status', MessageStatus::Skipped)->count());

        $guardianCopy = Message::where('recipient_name', 'Raj Kumar')->sole();
        $this->assertSame(MessageCategory::Announcement, $guardianCopy->category);
        $this->assertSame('Parent meeting', $guardianCopy->subject);
        $this->assertStringContainsString('Sunrise Public School: Parent meeting - Parent meeting scheduled Friday at 3 PM.', $guardianCopy->body);
        $this->assertStringNotContainsString('{', $guardianCopy->body);
        $this->assertNotNull($guardianCopy->announcement_id);
    }

    public function test_sms_only_skips_the_in_app_copies(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['channels' => 'sms'])
            ->assertCreated()
            ->assertJsonPath('in_app_count', 0)
            ->assertJsonPath('sms_count', 6);

        $this->assertSame(0, Message::where('channel', MessageChannel::InApp)->count());
        $this->assertSame(7, Message::where('channel', MessageChannel::Sms)->count());
    }

    public function test_in_app_only_reaches_staff_and_never_texts_a_guardian(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['channels' => 'in_app'])
            ->assertCreated()
            ->assertJsonPath('recipients_count', 4)
            ->assertJsonPath('sms_count', 0);

        $this->assertSame(4, Message::count());
        $this->assertSame(0, Message::where('channel', MessageChannel::Sms)->count());
    }

    public function test_an_in_app_only_notice_to_parents_is_refused_rather_than_sent_to_nobody(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['audience_type' => 'parents', 'channels' => 'in_app'])
            ->assertStatus(422)
            ->assertJsonPath('code', 'UNREACHABLE_AUDIENCE')
            ->assertJsonPath('message', 'Guardians have no app login, so this audience can only be reached by SMS.');

        $this->assertDatabaseCount('announcements', 0);
        $this->assertDatabaseCount('messages', 0);
    }

    public function test_the_parents_audience_reaches_only_guardians(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['audience_type' => 'parents'])
            ->assertCreated()
            // The count is who can actually be texted.
            ->assertJsonPath('recipients_count', 2);

        // Anita Rao has no number on record, so she gets a skipped row.
        $this->assertSame(3, Message::count());
        $this->assertSame(
            ['Anita Rao', 'Raj Kumar', 'Rohit Singh'],
            Message::orderBy('recipient_name')->pluck('recipient_name')->all(),
        );
    }

    public function test_the_teachers_audience_reaches_teachers_and_heads_but_not_other_staff(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['audience_type' => 'teachers'])
            ->assertCreated()
            ->assertJsonPath('recipients_count', 2);

        $recipients = Message::where('channel', MessageChannel::InApp)->pluck('user_id')->all();
        $this->assertEqualsCanonicalizing([$f['teacher']->id, $f['mathsHod']->id], $recipients);
    }

    public function test_a_class_audience_reaches_only_that_sections_guardians(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], [
            'audience_type' => 'class_section',
            'audience_id' => $f['section']->id,
        ])
            ->assertCreated()
            ->assertJsonPath('audience_label', 'Grade 8 A')
            // Arjun's guardian has a number; the other student in the section does not.
            ->assertJsonPath('recipients_count', 1);

        $this->assertSame('Anita Rao', Message::where('status', MessageStatus::Skipped)->sole()->recipient_name);
        $this->assertSame(
            'Raj Kumar',
            Message::where('status', '!=', MessageStatus::Skipped)->sole()->recipient_name,
        );
    }

    public function test_a_department_audience_reaches_that_departments_staff(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], [
            'audience_type' => 'department',
            'audience_id' => $f['maths']->id,
        ])
            ->assertCreated()
            ->assertJsonPath('audience_label', 'Mathematics')
            ->assertJsonPath('recipients_count', 2);

        $recipients = Message::where('channel', MessageChannel::InApp)->pluck('user_id')->all();
        $this->assertEqualsCanonicalizing([$f['teacher']->id, $f['mathsHod']->id], $recipients);
    }

    public function test_inactive_students_and_users_are_left_out(): void
    {
        $f = $this->makeSchool();
        $f['teacher']->update(['status' => 'inactive']);

        $this->publish($f['admin'], ['audience_type' => 'teachers'])
            ->assertCreated()
            ->assertJsonPath('recipients_count', 1);
    }

    public function test_a_school_with_sms_switched_off_still_delivers_in_app(): void
    {
        $f = $this->makeSchool();
        CommunicationSetting::factory()->forSchool($f['school'])->smsOff()->create();

        $this->publish($f['admin'])->assertCreated();

        $this->assertSame(4, Message::count());
        $this->assertSame(0, Message::where('channel', MessageChannel::Sms)->count());
    }

    // -- validation ------------------------------------------------------

    public function test_the_form_requires_a_title_a_body_an_audience_and_a_channel(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')->postJson(self::ANNOUNCEMENTS, [])
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['title', 'body', 'audience_type', 'channels']]]);
    }

    public function test_a_class_or_department_audience_must_name_its_target(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['audience_type' => 'class_section'])
            ->assertStatus(422)
            ->assertJsonPath('details.errors.audience_id.0', 'Pick the class or department this announcement is for.');
    }

    public function test_a_target_from_another_school_is_refused(): void
    {
        $f = $this->makeSchool();
        $other = $this->makeSchool();

        $this->publish($f['admin'], [
            'audience_type' => 'department',
            'audience_id' => $other['maths']->id,
        ])
            ->assertStatus(422)
            ->assertJsonPath('details.errors.audience_id.0', 'That class or department does not belong to this school.');

        $this->publish($f['admin'], [
            'audience_type' => 'class_section',
            'audience_id' => $other['section']->id,
        ])->assertStatus(422);
    }

    public function test_an_expiry_in_the_past_is_refused(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['expires_at' => '2026-09-01'])
            ->assertStatus(422)
            ->assertJsonPath('details.errors.expires_at.0', 'An expiry date cannot be in the past.');
    }

    public function test_a_title_or_body_that_is_too_short_is_refused(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['title' => 'Hi', 'body' => 'Too short'])
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['title', 'body']]]);
    }

    // -- authorization ---------------------------------------------------

    public function test_teachers_and_staff_cannot_publish_or_even_see_the_list(): void
    {
        $f = $this->makeSchool();

        foreach (['teacher', 'staff'] as $role) {
            $this->publish($f[$role])->assertForbidden();
            $this->actingAs($f[$role], 'sanctum')->getJson(self::ANNOUNCEMENTS)->assertForbidden();
        }
    }

    public function test_a_head_of_department_can_only_announce_to_their_own_department(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['mathsHod'], [
            'audience_type' => 'department',
            'audience_id' => $f['maths']->id,
        ])->assertCreated();

        $this->publish($f['mathsHod'], [
            'audience_type' => 'department',
            'audience_id' => $f['science']->id,
        ])->assertForbidden();

        $this->publish($f['mathsHod'])->assertForbidden();
        $this->publish($f['mathsHod'], ['audience_type' => 'parents'])->assertForbidden();
    }

    public function test_a_head_of_department_sees_only_their_own_departments_announcements(): void
    {
        $f = $this->makeSchool();
        Announcement::factory()->forSchool($f['school'])->create();
        $mine = Announcement::factory()->forDepartment($f['maths'])->create();
        Announcement::factory()->forDepartment($f['science'])->create();

        $this->actingAs($f['mathsHod'], 'sanctum')->getJson(self::ANNOUNCEMENTS.'/'.$mine->id)->assertOk();
        $this->actingAs($f['mathsHod'], 'sanctum')
            ->getJson(self::ANNOUNCEMENTS.'/'.Announcement::where('audience_label', 'Science')->sole()->id)
            ->assertForbidden();
    }

    public function test_a_head_of_department_only_sees_their_own_departments_notices_in_the_list(): void
    {
        $f = $this->makeSchool();
        Announcement::factory()->forSchool($f['school'])->create(['title' => 'Staff briefing']);
        Announcement::factory()->forDepartment($f['maths'])->create(['title' => 'Maths meeting']);
        Announcement::factory()->forDepartment($f['science'])->create(['title' => 'Science meeting']);

        $response = $this->actingAs($f['mathsHod'], 'sanctum')->getJson(self::ANNOUNCEMENTS);

        $response->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.title', 'Maths meeting');
    }

    public function test_a_guardian_with_no_mobile_is_recorded_as_skipped_rather_than_dropped(): void
    {
        $f = $this->makeSchool();

        $this->publish($f['admin'], ['audience_type' => 'parents'])->assertCreated();

        // Two reachable guardians plus the one with no number on record.
        $this->assertSame(3, Message::count());
        $skipped = Message::where('status', MessageStatus::Skipped)->sole();
        $this->assertSame('Anita Rao', $skipped->recipient_name);
        $this->assertSame('No mobile number on record.', $skipped->failure_reason);
        // The reach count still means "people we can actually text".
        $this->assertSame(2, Announcement::sole()->recipients_count);
    }

    public function test_an_admin_cannot_touch_another_schools_announcement(): void
    {
        $f = $this->makeSchool();
        $other = $this->makeSchool();
        $theirs = Announcement::factory()->forSchool($other['school'])->create();

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::ANNOUNCEMENTS.'/'.$theirs->id)->assertForbidden();
        $this->actingAs($f['admin'], 'sanctum')->deleteJson(self::ANNOUNCEMENTS.'/'.$theirs->id)->assertForbidden();
    }

    public function test_the_list_is_scoped_to_the_actors_school_and_a_super_admin_can_narrow_it(): void
    {
        $f = $this->makeSchool();
        $other = $this->makeSchool();
        Announcement::factory()->forSchool($f['school'])->create();
        Announcement::factory()->forSchool($other['school'])->create();

        $this->actingAs($f['admin'], 'sanctum')->getJson(self::ANNOUNCEMENTS)
            ->assertOk()->assertJsonCount(1, 'data');

        $this->actingAs($f['superAdmin'], 'sanctum')->getJson(self::ANNOUNCEMENTS)
            ->assertOk()->assertJsonCount(2, 'data');

        $this->actingAs($f['superAdmin'], 'sanctum')->getJson(self::ANNOUNCEMENTS.'?school_id='.$other['school']->id)
            ->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_the_endpoint_needs_a_signed_in_user(): void
    {
        $this->getJson(self::ANNOUNCEMENTS)->assertUnauthorized();
        $this->postJson(self::ANNOUNCEMENTS, [])->assertUnauthorized();
    }

    // -- the list, preview and deleting ----------------------------------

    public function test_the_list_filters_by_audience_search_term_and_active_only(): void
    {
        $f = $this->makeSchool();
        Announcement::factory()->forSchool($f['school'])->create(['title' => 'Sports day']);
        Announcement::factory()->forDepartment($f['maths'])->create(['title' => 'Syllabus review']);
        Announcement::factory()->forSchool($f['school'])->expiringOn('2026-09-10')->create(['title' => 'Old notice']);

        $admin = $this->actingAs($f['admin'], 'sanctum');

        $admin->getJson(self::ANNOUNCEMENTS.'?audience_type=department')->assertOk()->assertJsonCount(1, 'data');
        $admin->getJson(self::ANNOUNCEMENTS.'?q=Sports')->assertOk()->assertJsonCount(1, 'data');
        $admin->getJson(self::ANNOUNCEMENTS.'?active_only=1')->assertOk()->assertJsonCount(2, 'data');
        $admin->getJson(self::ANNOUNCEMENTS)->assertOk()
            ->assertJsonCount(3, 'data')
            ->assertJsonStructure(['data' => [['id', 'title', 'audience_label', 'recipients_count']], 'meta' => ['total']]);
    }

    public function test_the_preview_reports_how_many_people_an_audience_reaches(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['admin'], 'sanctum')
            ->getJson(self::ANNOUNCEMENTS.'/preview?audience_type=class_section&channels=sms_in_app&audience_id='.$f['section']->id)
            ->assertOk()
            ->assertJsonPath('recipients', 1)
            ->assertJsonPath('audience_label', 'Grade 8 A');

        $this->actingAs($f['admin'], 'sanctum')
            ->getJson(self::ANNOUNCEMENTS.'/preview?audience_type=all_school&channels=in_app')
            ->assertOk()
            ->assertJsonPath('recipients', 4)
            ->assertJsonPath('sms', 0);
    }

    public function test_the_preview_never_names_another_schools_class_or_department(): void
    {
        $theirs = $this->makeSchool();
        $ours = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        // The same generic label a target that does not exist at all gets, so
        // trying ids reveals nothing about another school.
        $this->actingAs($ours, 'sanctum')
            ->getJson(self::ANNOUNCEMENTS.'/preview?audience_type=class_section&channels=sms_in_app&audience_id='.$theirs['section']->id)
            ->assertOk()
            ->assertJsonPath('recipients', 0)
            ->assertJsonPath('audience_label', 'Class');

        $this->actingAs($ours, 'sanctum')
            ->getJson(self::ANNOUNCEMENTS.'/preview?audience_type=department&channels=in_app&audience_id='.$theirs['maths']->id)
            ->assertOk()
            ->assertJsonPath('audience_label', 'Department');
    }

    public function test_a_head_of_department_cannot_preview_another_department(): void
    {
        $f = $this->makeSchool();

        $this->actingAs($f['mathsHod'], 'sanctum')
            ->getJson(self::ANNOUNCEMENTS.'/preview?audience_type=department&channels=in_app&audience_id='.$f['science']->id)
            ->assertForbidden();
    }

    public function test_deleting_drops_it_from_the_feed_but_keeps_the_log_honest(): void
    {
        $f = $this->makeSchool();
        $this->publish($f['admin'])->assertCreated();
        $announcement = Announcement::sole();

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()->assertJsonCount(1, 'data');

        $this->actingAs($f['admin'], 'sanctum')->deleteJson(self::ANNOUNCEMENTS.'/'.$announcement->id)
            ->assertNoContent();

        $this->assertSoftDeleted('announcements', ['id' => $announcement->id]);
        // The texts that already went out are still in the log.
        $this->assertSame(11, Message::count());
        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_an_expired_announcement_leaves_the_feed_on_its_own(): void
    {
        $f = $this->makeSchool();
        $this->publish($f['admin'], ['expires_at' => '2026-09-17'])->assertCreated();

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()->assertJsonCount(1, 'data');

        Carbon::setTestNow('2026-09-18 09:00:00');

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()->assertJsonCount(0, 'data');
        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox/unread-count')
            ->assertOk()->assertJsonPath('unread', 0);
    }

    public function test_the_in_app_copy_carries_the_title_as_its_subject(): void
    {
        $f = $this->makeSchool();
        $this->publish($f['admin'], ['title' => 'Sports day moved'])->assertCreated();

        $this->actingAs($f['teacher'], 'sanctum')->getJson('/api/v1/inbox')
            ->assertOk()
            ->assertJsonPath('data.0.subject', 'Sports day moved')
            ->assertJsonPath('data.0.category', 'announcement');
    }

    public function test_announcements_show_up_in_the_communication_log_under_their_own_category(): void
    {
        $f = $this->makeSchool();
        $this->publish($f['admin'], ['audience_type' => 'parents'])->assertCreated();

        $this->actingAs($f['admin'], 'sanctum')->getJson('/api/v1/communication/messages?category=announcement')
            ->assertOk()
            ->assertJsonCount(3, 'data')
            ->assertJsonPath('data.0.event_label', 'Announcement');
    }

    public function test_every_audience_and_channel_pair_reports_a_label(): void
    {
        foreach (AnnouncementAudience::cases() as $audience) {
            $this->assertNotEmpty($audience->label());
        }

        foreach (AnnouncementChannels::cases() as $channels) {
            $this->assertNotEmpty($channels->label());
            $this->assertNotEmpty($channels->messageChannels());
        }

        $this->assertTrue(AnnouncementAudience::Parents->reachesGuardians());
        $this->assertFalse(AnnouncementAudience::Parents->reachesStaff());
        $this->assertTrue(AnnouncementAudience::Department->needsTarget());
    }
}
