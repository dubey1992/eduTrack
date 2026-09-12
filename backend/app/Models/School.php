<?php

namespace App\Models;

use App\Enums\SchoolStatus;
use App\Support\SchoolClock;
use Database\Factories\SchoolFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

#[Fillable([
    'name', 'registration_number', 'email', 'phone', 'address', 'city',
    'state', 'country', 'postal_code', 'currency_code', 'timezone', 'logo_url',
    'status',
])]
// 'status' is fillable here for the same reason as User::status (Phase 1):
// SchoolService sets it explicitly on create/activate/deactivate, and the
// general update() request never includes it in its validated payload.
class School extends Model
{
    /** @use HasFactory<SchoolFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'status' => SchoolStatus::class,
        ];
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
