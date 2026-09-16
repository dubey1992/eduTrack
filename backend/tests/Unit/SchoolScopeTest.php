<?php

namespace Tests\Unit;

use App\Enums\UserRole;
use App\Models\User;
use App\Support\SchoolScope;
use Illuminate\Database\Query\Builder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * The one question multi-tenancy turns on, now asked in one place.
 *
 * These are the rules the whole of isolation rests on, so they are checked
 * directly rather than only through the endpoints that use them.
 */
class SchoolScopeTest extends TestCase
{
    // Needs the schema, though almost nothing here needs a row in it.
    // Resolving an admin's scope reads the schools table to find the group,
    // so these assertions cannot be made against no database at all - which
    // is how they passed on a developer machine whose test database still had
    // tables from an earlier run, and failed the moment CI ran them on a
    // fresh one.
    use RefreshDatabase;

    private function actor(UserRole $role, ?int $schoolId): User
    {
        // Not persisted, and deliberately with no School attached: every
        // assertion in this file is about the rules themselves, so nothing
        // here should depend on a row existing. For an admin role that means
        // these exercise the fallback in groupOf() - which is the point of
        // the test below.
        $user = new User;
        $user->role = $role;
        $user->school_id = $schoolId;

        return $user;
    }

    private function students(): Builder
    {
        return DB::table('students');
    }

    // ── an unrestricted actor ───────────────────────────────────────────

    public function test_a_super_admin_may_touch_any_school(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SuperAdmin, null));

        $this->assertTrue($scope->isUnrestricted());
        $this->assertTrue($scope->allows(1));
        $this->assertTrue($scope->allows(9999));
        $this->assertNull($scope->ids());
    }

    public function test_an_unrestricted_query_is_left_alone(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SuperAdmin, null));

        $this->assertStringNotContainsString('school_id', $scope->applyTo($this->students())->toSql());
    }

    public function test_an_unrestricted_actor_narrows_to_the_school_they_asked_for(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SuperAdmin, null));
        $query = $scope->applyTo($this->students(), 7);

        $this->assertStringContainsString('"school_id" = ?', str_replace('`', '"', $query->toSql()));
        $this->assertSame([7], $query->getBindings());
    }

    public function test_an_unrestricted_actor_writes_where_they_say(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SuperAdmin, null));

        $this->assertSame(7, $scope->writableSchoolId(7));
        // Nothing to fall back on - the request has to name a school, which
        // is what the validation rule is for.
        $this->assertNull($scope->writableSchoolId(null));
        $this->assertNull($scope->defaultSchoolId());
    }

    // ── an actor pinned to one school ───────────────────────────────────

    #[DataProvider('schoolRoles')]
    public function test_every_other_role_is_pinned_to_its_own_school(UserRole $role): void
    {
        $scope = SchoolScope::for($this->actor($role, 4));

        $this->assertFalse($scope->isUnrestricted());
        $this->assertSame([4], $scope->ids());
        $this->assertTrue($scope->allows(4));
        $this->assertFalse($scope->allows(5));
        $this->assertSame(4, $scope->defaultSchoolId());
    }

    /**
     * @return array<string, array{UserRole}>
     */
    public static function schoolRoles(): array
    {
        return [
            'school admin' => [UserRole::SchoolAdmin],
            'hod' => [UserRole::Hod],
            'teacher' => [UserRole::Teacher],
            'staff' => [UserRole::Staff],
            'transport manager' => [UserRole::TransportManager],
        ];
    }

    public function test_an_admin_whose_school_cannot_be_read_keeps_their_own(): void
    {
        // A School Admin normally resolves to their school's whole group,
        // which needs the school row. Without one - deleted underneath them,
        // or an account built in memory - they fall back to the id on the
        // account rather than to nothing, so they still see their own
        // records instead of an empty screen with no explanation.
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, 4));

        $this->assertSame([4], $scope->ids());
        $this->assertSame(4, $scope->defaultSchoolId());
    }

    public function test_an_account_with_no_school_at_all_sees_nothing(): void
    {
        // Never "no filter": a null school_id must not quietly match every
        // record whose school_id is also null.
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, null));

        $this->assertFalse($scope->isUnrestricted());
        $this->assertSame([], $scope->ids());
        $this->assertFalse($scope->allows(null));
        $this->assertNull($scope->defaultSchoolId());
    }

    public function test_a_pinned_query_is_limited_to_that_school(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, 4));
        $query = $scope->applyTo($this->students());

        $this->assertStringContainsString('school_id', $query->toSql());
        $this->assertSame([4], $query->getBindings());
    }

    public function test_asking_for_another_school_is_ignored_not_honoured(): void
    {
        // The rule the hand-written version enforced, kept exactly: a filter
        // can narrow within the scope but never widen past it. Somebody who
        // edits school_id in a request sees their own records, not a stranger's.
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, 4));
        $query = $scope->applyTo($this->students(), 9);

        $this->assertSame([4], $query->getBindings());
    }

    public function test_asking_for_your_own_school_is_harmless(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, 4));
        $query = $scope->applyTo($this->students(), 4);

        $this->assertSame([4, 4], $query->getBindings());
    }

    public function test_a_pinned_actor_always_writes_into_their_own_school(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, 4));

        $this->assertSame(4, $scope->writableSchoolId(null));
        $this->assertSame(4, $scope->writableSchoolId(4));
        // The client's school_id is never trusted (CLAUDE.md rule 10).
        $this->assertSame(4, $scope->writableSchoolId(9));
    }

    // ── the edges ───────────────────────────────────────────────────────

    public function test_an_account_with_no_school_can_see_nothing(): void
    {
        // Should not happen outside a half-finished fixture, but if it does,
        // the answer is "nothing" - not "every record whose school_id is also
        // null", which is what a bare === comparison used to give.
        $scope = SchoolScope::for($this->actor(UserRole::Teacher, null));

        $this->assertFalse($scope->isUnrestricted());
        $this->assertSame([], $scope->ids());
        $this->assertFalse($scope->allows(null));
        $this->assertFalse($scope->allows(1));
        $this->assertNull($scope->writableSchoolId(1));
    }

    public function test_a_null_school_never_slips_past_a_restricted_scope(): void
    {
        $scope = SchoolScope::for($this->actor(UserRole::SchoolAdmin, 4));

        $this->assertFalse($scope->allows(null));
    }

    public function test_an_unrestricted_scope_allows_even_a_null_school(): void
    {
        // A Super Admin managing a record that belongs to no school - their
        // own account, for instance.
        $this->assertTrue(SchoolScope::unrestricted()->allows(null));
    }

    public function test_a_scope_over_several_schools_allows_each_of_them(): void
    {
        // The shape a school group will use. Nothing builds one yet.
        $scope = SchoolScope::of([2, 5, 8]);

        $this->assertFalse($scope->isUnrestricted());
        $this->assertTrue($scope->allows(2));
        $this->assertTrue($scope->allows(8));
        $this->assertFalse($scope->allows(3));
        // Ambiguous on purpose: a write has to say which one.
        $this->assertNull($scope->defaultSchoolId());
        $this->assertNull($scope->writableSchoolId(null));
        $this->assertSame(5, $scope->writableSchoolId(5));
        $this->assertNull($scope->writableSchoolId(3));
    }

    public function test_a_scope_over_several_schools_narrows_to_one_of_them(): void
    {
        $scope = SchoolScope::of([2, 5, 8]);
        $query = $scope->applyTo($this->students(), 5);

        $this->assertSame([2, 5, 8, 5], $query->getBindings());
    }

    public function test_duplicates_in_a_scope_are_collapsed(): void
    {
        $this->assertSame([2, 5], SchoolScope::of([2, 5, 2, 5])->ids());
    }

    public function test_a_custom_column_can_be_scoped(): void
    {
        // Some queries reach the school through a join alias.
        $scope = SchoolScope::of([3]);
        $sql = str_replace('`', '"', $scope->applyTo($this->students(), null, 'schools.id')->toSql());

        $this->assertStringContainsString('"schools"."id"', $sql);
    }
}
