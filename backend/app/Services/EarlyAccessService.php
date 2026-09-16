<?php

namespace App\Services;

use App\Enums\EarlyAccessStatus;
use App\Models\EarlyAccessRequest;
use App\Models\School;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;

class EarlyAccessService
{
    /**
     * Records a school's interest.
     *
     * A school that submits the form twice updates its own open request
     * rather than raising a second one - somebody re-reading the page and
     * filling it in again is not two schools, and a panel full of duplicates
     * is a panel nobody trusts. Once a request has been declined or
     * converted, though, a new approach is genuinely new.
     *
     * @param  array<string, mixed>  $data
     */
    public function record(array $data): EarlyAccessRequest
    {
        $existing = EarlyAccessRequest::query()
            ->where('email', $data['email'])
            ->whereIn('status', [EarlyAccessStatus::New, EarlyAccessStatus::Contacted])
            ->latest('id')
            ->first();

        if ($existing !== null) {
            // Their latest answers win - they may be correcting a typo - but
            // the request keeps its place in the queue and whatever status
            // somebody has already given it.
            $existing->update($data);

            return $existing->fresh();
        }

        return EarlyAccessRequest::create([...$data, 'status' => EarlyAccessStatus::New]);
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(array $filters): LengthAwarePaginator
    {
        return EarlyAccessRequest::query()
            ->with(['convertedSchool', 'reviewedBy'])
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->when($filters['q'] ?? null, function ($query, string $term) {
                $like = '%'.$term.'%';
                $query->where(fn ($query) => $query
                    ->whereLike('school_name', $like, caseSensitive: false)
                    ->orWhereLike('contact_name', $like, caseSensitive: false)
                    ->orWhereLike('email', $like, caseSensitive: false));
            })
            // Newest first: the panel is a queue, and the thing nobody has
            // looked at yet is the thing that matters.
            ->latest('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function review(EarlyAccessRequest $request, array $data, User $actor): EarlyAccessRequest
    {
        $request->update([
            ...$data,
            'reviewed_by' => $actor->id,
            'reviewed_at' => now(),
        ]);

        return $request->fresh(['convertedSchool', 'reviewedBy']);
    }

    /**
     * Marks a request as having become a school.
     *
     * Set by the system when the school is actually created, never by hand -
     * a list that says "Converted" with no school behind it is worse than one
     * that says nothing.
     */
    public function markConverted(EarlyAccessRequest $request, School $school, User $actor): EarlyAccessRequest
    {
        return $this->review($request, [
            'status' => EarlyAccessStatus::Converted,
            'converted_school_id' => $school->id,
        ], $actor);
    }

    /**
     * How many requests are waiting on somebody, for the sidebar badge.
     */
    public function openCount(): int
    {
        return EarlyAccessRequest::query()
            ->whereIn('status', [EarlyAccessStatus::New, EarlyAccessStatus::Contacted])
            ->count();
    }
}
