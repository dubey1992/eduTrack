<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\DashboardService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function __construct(private readonly DashboardService $dashboard) {}

    /**
     * The landing screen's figures for whoever is asking.
     *
     * No authorization gate: every signed-in user has a dashboard, and what
     * it contains is decided by their role inside the service rather than by
     * anything they send. A school user's figures are always their own
     * school's - the school_id filter is only read for a Super Admin.
     */
    public function index(Request $request): JsonResponse
    {
        return response()->json(
            $this->dashboard->forUser($request->user(), $request->only('school_id'))
        );
    }
}
