<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * An email address identifies one person, whatever case it is typed in.
 *
 * Written for the PostgreSQL migration (docs/python-migration.md, M2). MySQL's
 * default collation is case-insensitive, so today `Head@school.test` and
 * `head@school.test` cannot both exist and either spelling signs the same
 * person in. PostgreSQL compares case-sensitively: without this, the same data
 * would allow two accounts for one person, one of them unreachable by whoever
 * typed the other spelling, and an invitation sent to a capitalised address
 * would create a second account rather than being refused as a duplicate.
 *
 * That is an authentication boundary changing meaning, which is why it is
 * pinned here rather than left to the database's collation to decide.
 */
class EmailCaseTest extends TestCase
{
    use RefreshDatabase;

    private School $school;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->school = School::factory()->create();
        $this->admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->school)->create();
    }

    public function test_the_same_address_in_another_case_is_a_duplicate(): void
    {
        User::factory()->role(UserRole::Teacher)->forSchool($this->school)->create([
            'email' => 'head@school.test',
        ]);

        $this->actingAs($this->admin, 'sanctum')
            ->postJson('/api/v1/users', [
                'first_name' => 'Anita',
                'last_name' => 'Rao',
                'email' => 'Head@School.test',
                'password' => 'password123',
                'role' => UserRole::SchoolAdmin->value,
            ])
            ->assertStatus(422)
            ->assertJsonStructure(['details' => ['errors' => ['email']]]);

        $this->assertSame(1, User::query()->whereRaw('lower(email) = ?', ['head@school.test'])->count());
    }

    public function test_an_address_is_stored_lowercase(): void
    {
        // Normalising on write is what makes the uniqueness rule enforceable
        // by an index rather than only by a validation rule - and a validation
        // rule alone loses every race.
        $this->actingAs($this->admin, 'sanctum')
            ->postJson('/api/v1/users', [
                'first_name' => 'Anita',
                'last_name' => 'Rao',
                'email' => 'Anita.Rao@School.TEST',
                'password' => 'password123',
                'role' => UserRole::SchoolAdmin->value,
            ])
            ->assertCreated()
            ->assertJsonPath('email', 'anita.rao@school.test');
    }

    public function test_signing_in_works_whatever_case_the_address_is_typed(): void
    {
        User::factory()->role(UserRole::SchoolAdmin)->forSchool($this->school)->create([
            'email' => 'principal@school.test',
            'password' => Hash::make('password123'),
        ]);

        foreach (['principal@school.test', 'Principal@School.test', 'PRINCIPAL@SCHOOL.TEST'] as $typed) {
            $this->postJson('/api/v1/auth/login', ['email' => $typed, 'password' => 'password123'])
                ->assertOk()
                ->assertJsonPath('user.email', 'principal@school.test');
        }
    }

    public function test_the_database_itself_refuses_a_duplicate_in_another_case(): void
    {
        // The rule above can be raced; this one cannot. Two requests arriving
        // together both pass validation and only one can reach the table.
        User::factory()->role(UserRole::Teacher)->forSchool($this->school)->create([
            'email' => 'clash@school.test',
        ]);

        $this->expectException(QueryException::class);

        User::factory()->role(UserRole::Teacher)->forSchool($this->school)->create([
            'email' => 'CLASH@school.test',
        ]);
    }
}
