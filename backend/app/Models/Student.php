<?php

namespace App\Models;

use App\Enums\StudentStatus;
use Database\Factories\StudentFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

#[Fillable([
    'school_id', 'class_section_id', 'admission_number', 'first_name', 'last_name',
    'roll_number', 'guardian_name', 'guardian_mobile', 'address', 'status',
])]
class Student extends Model
{
    /** @use HasFactory<StudentFactory> */
    use HasFactory;

    protected function casts(): array
    {
        return [
            'status' => StudentStatus::class,
        ];
    }

    /**
     * Convenience accessor for display - not a stored column.
     */
    protected function name(): Attribute
    {
        return Attribute::get(fn () => trim("{$this->first_name} {$this->last_name}"));
    }

    /**
     * @return BelongsTo<School, $this>
     */
    public function school(): BelongsTo
    {
        return $this->belongsTo(School::class);
    }

    /**
     * @return BelongsTo<ClassSection, $this>
     */
    public function classSection(): BelongsTo
    {
        return $this->belongsTo(ClassSection::class);
    }

    /**
     * The student's current transport route + stop, if they use school
     * transport (Phase 14).
     *
     * @return HasOne<StudentTransportAssignment, $this>
     */
    public function transportAssignment(): HasOne
    {
        return $this->hasOne(StudentTransportAssignment::class);
    }

    public function isActive(): bool
    {
        return $this->status === StudentStatus::Active;
    }
}
