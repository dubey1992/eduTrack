<?php

namespace App\Exceptions;

use Illuminate\Auth\Access\AuthorizationException;
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
            'details' => $details,
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
            $e instanceof AuthenticationException => [
                401,
                'UNAUTHENTICATED',
                'Authentication is required to access this resource.',
                [],
            ],
            $e instanceof AuthorizationException => [
                403,
                'FORBIDDEN',
                'You are not authorized to perform this action.',
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
