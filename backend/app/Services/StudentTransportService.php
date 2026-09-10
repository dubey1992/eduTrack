<?php

namespace App\Services;

use App\Exceptions\RouteCapacityFullException;
use App\Models\Student;
use App\Models\StudentTransportAssignment;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class StudentTransportService
{
    /**
     * Assigns (or re-assigns) a student to a route + stop. Capacity is the
     * route's vehicle's seat count; a route with no vehicle yet has no
     * limit (decided 2026-09-10). Moving a student between stops on the
     * same route never counts them twice.
     */
    public function assign(Student $student, TransportRoute $route, TransportStop $stop): StudentTransportAssignment
    {
        return DB::transaction(function () use ($student, $route, $stop) {
            $capacity = $route->vehicle?->capacity;
            if ($capacity !== null) {
                $others = $route->assignments()->where('student_id', '!=', $student->id)->count();
                if ($others >= $capacity) {
                    throw new RouteCapacityFullException(
                        "{$route->label()} is full - its vehicle seats {$capacity} students."
                    );
                }
            }

            return StudentTransportAssignment::updateOrCreate(
                ['student_id' => $student->id],
                ['school_id' => $student->school_id, 'route_id' => $route->id, 'transport_stop_id' => $stop->id]
            );
        });
    }

    public function unassign(Student $student): void
    {
        $student->transportAssignment()->delete();
    }

    /**
     * The students riding a route, in stop order then by name.
     *
     * @param  array<string, mixed>  $filters
     */
    public function studentsOnRoute(TransportRoute $route, array $filters): LengthAwarePaginator
    {
        return StudentTransportAssignment::query()
            ->where('student_transport_assignments.route_id', $route->id)
            ->with(['student.classSection.schoolClass', 'stop'])
            ->join('transport_stops', 'transport_stops.id', '=', 'student_transport_assignments.transport_stop_id')
            ->join('students', 'students.id', '=', 'student_transport_assignments.student_id')
            ->orderBy('transport_stops.sequence_number')
            ->orderBy('students.first_name')
            ->select('student_transport_assignments.*')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }
}
