<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\ForgotPasswordRequest;
use App\Http\Requests\Auth\ResetPasswordRequest;
use App\Services\PasswordResetService;
use Illuminate\Http\JsonResponse;

class PasswordResetController extends Controller
{
    public function __construct(private readonly PasswordResetService $passwordResetService) {}

    public function forgot(ForgotPasswordRequest $request): JsonResponse
    {
        $this->passwordResetService->sendResetLink($request->string('email')->toString());

        // Always the same response, whether or not the email is registered.
        return response()->json([
            'message' => 'If an account exists for that email, a password reset link has been sent.',
        ]);
    }

    public function reset(ResetPasswordRequest $request): JsonResponse
    {
        $reset = $this->passwordResetService->reset(
            $request->string('email')->toString(),
            $request->string('token')->toString(),
            $request->string('password')->toString(),
        );

        if (! $reset) {
            return response()->json([
                'code' => 'INVALID_RESET_TOKEN',
                'message' => 'This password reset link is invalid or has expired.',
                // An empty object, like every other error: PHP writes an
                // empty array as `[]`, and the envelope promises `{}`.
                'details' => new \stdClass,
            ], 422);
        }

        return response()->json(['message' => 'Password reset successfully.']);
    }
}
