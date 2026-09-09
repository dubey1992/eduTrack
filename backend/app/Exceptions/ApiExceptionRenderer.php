<?php

namespace App\Exceptions;

use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;
use Throwable;

/**
 * Maps any exception raised on the API to the project's standard JSON error
 * shape (code, message, details) and makes sure internal details never leak
 * to the client. See CLAUDE.md rule 16 (API Response Standard).
 */
class ApiExceptionRenderer
{
    public static function render(Throwable $e, Request $request): JsonResponse
    {
        [$status, $code, $message, $details] = self::describe($e);

        return response()->json([
            'code' => $code,
            'message' => $message,
            // PHP's [] json_encodes as a JSON array, not an object - every
            // branch below defaults $details to [] when there's nothing to
            // report, which the Flutter client can't parse as the object it
            // expects (`Map<String, dynamic>`). Force it to {} here, once,
            // rather than relying on every branch getting this right.
            'details' => empty($details) ? (object) [] : $details,
        ], $status);
    }

    /**
     * @return array{0: int, 1: string, 2: string, 3: array<string, mixed>}
     */
    private static function describe(Throwable $e): array
    {
        return match (true) {
            $e instanceof ValidationException => [
                422,
                'VALIDATION_ERROR',
                'The given data was invalid.',
                ['errors' => $e->errors()],
            ],
            $e instanceof AccountInactiveException => [
                403,
                'ACCOUNT_INACTIVE',
                $e->getMessage(),
                [],
            ],
            $e instanceof HasDependentRecordsException => [
                409,
                'HAS_DEPENDENT_RECORDS',
                $e->getMessage(),
                [],
            ],
            $e instanceof AttendanceAlreadySubmittedException => [
                409,
                'ATTENDANCE_ALREADY_SUBMITTED',
                $e->getMessage(),
                [],
            ],
            $e instanceof LeaveOverlapException => [
                409,
                'LEAVE_OVERLAP',
                $e->getMessage(),
                [],
            ],
            $e instanceof LeaveAlreadyReviewedException => [
                409,
                'LEAVE_ALREADY_REVIEWED',
                $e->getMessage(),
                [],
            ],
            $e instanceof StaffProfileRequiredException => [
                409,
                'STAFF_PROFILE_REQUIRED',
                $e->getMessage(),
                [],
            ],
            $e instanceof TeacherScheduleConflictException => [
                409,
                'TEACHER_SCHEDULE_CONFLICT',
                $e->getMessage(),
                [],
            ],
            $e instanceof TeachingReportAlreadySubmittedException => [
                409,
                'TEACHING_REPORT_ALREADY_SUBMITTED',
                $e->getMessage(),
                [],
            ],
            $e instanceof TeachingReportAlreadyReviewedException => [
                409,
                'TEACHING_REPORT_ALREADY_REVIEWED',
                $e->getMessage(),
                [],
            ],
            // Covers both "no/invalid token on a protected route" (Sanctum's
            // own generic "Unauthenticated." message) and AuthService's
            // deliberate throw for a failed login attempt (its own specific
            // "These credentials do not match our records.") - the specific
            // message must reach the client, not be replaced by a generic one.
            $e instanceof AuthenticationException => [
                401,
                'UNAUTHENTICATED',
                $e->getMessage() !== '' ? $e->getMessage() : 'Authentication is required to access this resource.',
                [],
            ],
            $e instanceof ModelNotFoundException, $e instanceof NotFoundHttpException => [
                404,
                'NOT_FOUND',
                'The requested resource was not found.',
                [],
            ],
            $e instanceof TooManyRequestsHttpException => [
                429,
                'TOO_MANY_REQUESTS',
                'Too many requests. Please try again later.',
                [],
            ],
            // Laravel's own exception handling converts AuthorizationException
            // into a plain 403 HttpException before this renders, so it's
            // caught here by status code rather than by an `instanceof` check.
            $e instanceof HttpExceptionInterface && $e->getStatusCode() === 403 => [
                403,
                'FORBIDDEN',
                'You are not authorized to perform this action.',
                [],
            ],
            $e instanceof HttpExceptionInterface => [
                $e->getStatusCode(),
                'HTTP_ERROR',
                $e->getMessage() !== '' ? $e->getMessage() : 'An error occurred while processing the request.',
                [],
            ],
            default => [
                500,
                'SERVER_ERROR',
                'Something went wrong. Please try again later.',
                config('app.debug') ? ['exception' => $e->getMessage()] : [],
            ],
        };
    }
}
