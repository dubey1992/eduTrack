<?php

namespace App\Models;

use App\Enums\TransportStatus;
use Database\Factories\DriverFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

#[Fillable(['school_id', 'name', 'mobile', 'licence_number', 'licence_expiry', 'status'])]
class Driver extends Model
{
    /** @use HasFactory<DriverFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'licence_expiry' => 'date',
            'status' => TransportStatus::class,
        ];
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * The route this driver currently serves, if any.
     *
     * @return HasOne<TransportRoute, $this>
     */
    public function route(): HasOne
    {
        return $this->hasOne(TransportRoute::class);
    }
}
