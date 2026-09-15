<?php

namespace App\Models;

use App\Enums\EarlyAccessStatus;
use Database\Factories\EarlyAccessRequestFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_name', 'contact_name', 'contact_role', 'email', 'phone',
    'city', 'country', 'expected_students', 'current_software', 'message',
    'status', 'notes', 'converted_school_id', 'reviewed_by', 'reviewed_at',
])]
class EarlyAccessRequest extends Model
{
    /** @use HasFactory<EarlyAccessRequestFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'status' => EarlyAccessStatus::class,
            'expected_students' => 'integer',
            'reviewed_at' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function convertedSchool(): BelongsTo
    {
        return $this->belongsTo(School::class, 'converted_school_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}
