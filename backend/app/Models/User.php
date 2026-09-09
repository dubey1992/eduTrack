<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use App\Enums\UserRole;
use App\Enums\UserStatus;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

#[Fillable(['first_name', 'last_name', 'email', 'mobile', 'password', 'role', 'status', 'school_id'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * @return HasOne<StaffProfile, $this>
     */
    public function staffProfile(): HasOne
    {
        return $this->hasOne(StaffProfile::class);
    }

    /**
     * Class sections where this user is the class teacher - the "Assigned
     * Classes" the prototype shows on the Teachers & Staff screen, derived
     * from Phase 4's class_sections.class_teacher_id rather than a new
     * teaching-assignment table (that belongs to Timetable, Phase 10).
     *
     * @return HasMany<ClassSection, $this>
     */
    public function classTeacherOf(): HasMany
    {
        return $this->hasMany(ClassSection::class, 'class_teacher_id');
    }

    /**
     * Subjects where this user is the lead teacher, mirroring classTeacherOf().
     *
     * @return HasMany<Subject, $this>
     */
    public function leadTeacherOfSubjects(): HasMany
    {
        return $this->hasMany(Subject::class, 'lead_teacher_id');
    }

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => UserRole::class,
            'status' => UserStatus::class,
        ];
    }

    /**
     * Convenience accessor for display/notifications - not a stored column.
     */
    protected function name(): Attribute
    {
        return Attribute::get(fn () => trim("{$this->first_name} {$this->last_name}"));
    }

    public function isActive(): bool
    {
        return $this->status === UserStatus::Active;
    }
}
