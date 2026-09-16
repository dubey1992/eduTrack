<?php

namespace App\Models;

use App\Enums\SchoolStatus;
use App\Support\SchoolClock;
use Database\Factories\SchoolFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

#[Fillable([
    'parent_school_id',
    'name', 'registration_number', 'email', 'phone', 'address', 'city',
    'state', 'country', 'postal_code', 'latitude', 'longitude',
    'currency_code', 'timezone', 'logo_url',
    'status',
])]
// 'status' is fillable here for the same reason as User::status (Phase 1):
// SchoolService sets it explicitly on create/activate/deactivate, and the
// general update() request never includes it in its validated payload.
class School extends Model
{
    /** @use HasFactory<SchoolFactory> */
    use HasFactory;

    /**
     * Memoised by groupSchoolIds(). Not an attribute - it is derived, and
     * lives only as long as this instance does.
     *
     * @var array<int, int>|null
     */
    private ?array $groupSchoolIds = null;

    protected function casts(): array
    {
        return [
            'status' => SchoolStatus::class,
            'latitude' => 'decimal:7',
            'longitude' => 'decimal:7',
        ];
    }

    /**
     * The group this school belongs to, if it is a branch of one.
     *
     * @return BelongsTo<School, $this>
     */
    public function parent(): BelongsTo
    {
        return $this->belongsTo(School::class, 'parent_school_id');
    }

    /**
     * The branches beneath this school, if it is a parent.
     *
     * @return HasMany<School, $this>
     */
    public function branches(): HasMany
    {
        return $this->hasMany(School::class, 'parent_school_id');
    }

    public function isBranch(): bool
    {
        return $this->parent_school_id !== null;
    }

    /**
     * Every school in this one's group - itself, plus its branches if it is a
     * parent, or its parent and siblings if it is a branch.
     *
     * Deliberately one level deep: a group of groups would need a recursive
     * query here and everywhere that calls it, and buys nothing a school has
     * asked for. Validation stops the data ever becoming deeper than this.
     *
     * Held on the instance after the first call. Every School Admin's scope
     * now resolves through here, and a scope is built once per policy check -
     * so a list of fifty students would otherwise ask the same question fifty
     * times (CLAUDE.md rule 22).
     *
     * @return array<int, int>
     */
    public function groupSchoolIds(): array
    {
        $rootId = $this->parent_school_id ?? $this->id;

        return $this->groupSchoolIds ??= School::query()
            ->where('id', $rootId)
            ->orWhere('parent_school_id', $rootId)
            ->orderBy('id')
            ->pluck('id')
            ->all();
    }

    /**
     * @return HasMany<User, $this>
     */
    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    /**
     * @return HasOne<CommunicationSetting, $this>
     */
    public function communicationSetting(): HasOne
    {
        return $this->hasOne(CommunicationSetting::class);
    }

    /**
     * What time it is at this school. Anything that decides a date - "is this
     * today?", "what month is this?" - asks here rather than the server.
     */
    public function clock(): SchoolClock
    {
        return SchoolClock::for($this);
    }

    public function isActive(): bool
    {
        return $this->status === SchoolStatus::Active;
    }
}
