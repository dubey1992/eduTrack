<?php

namespace App\Models;

use App\Enums\StaffAttendanceStatus;
use Database\Factories\StaffAttendanceFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'school_id', 'staff_profile_id', 'attendance_date', 'status',
    'check_in', 'check_out', 'remarks', 'marked_by',
])]
class StaffAttendance extends Model
{
    /** @use HasFactory<StaffAttendanceFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'attendance_date' => 'date',
            'status' => StaffAttendanceStatus::class,
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
     * @return BelongsTo<StaffProfile, $this>
     */
    public function staffProfile(): BelongsTo
    {
        return $this->belongsTo(StaffProfile::class);
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function markedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'marked_by');
    }
}
