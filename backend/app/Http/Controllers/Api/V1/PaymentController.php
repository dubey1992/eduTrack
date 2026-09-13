<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Payments\StorePaymentRequest;
use App\Http\Requests\Payments\UpdatePaymentRequest;
use App\Http\Resources\PaymentResource;
use App\Models\Payment;
use App\Services\PaymentReceiptService;
use App\Services\PaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class PaymentController extends Controller
{
    public function __construct(private readonly PaymentService $paymentService) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', Payment::class);

        $payments = $this->paymentService->paginate($request->only(['school_id', 'status', 'payment_type', 'per_page']));

        return PaymentResource::collection($payments);
    }

    public function store(StorePaymentRequest $request): JsonResponse
    {
        $payment = $this->paymentService->create($request->validated(), $request->user());
        $payment->load(['school', 'creator']);

        return (new PaymentResource($payment))->response()->setStatusCode(201);
    }

    public function show(Payment $payment): PaymentResource
    {
        Gate::authorize('view', $payment);

        return new PaymentResource($payment->load(['school', 'creator']));
    }

    public function update(UpdatePaymentRequest $request, Payment $payment): PaymentResource
    {
        $payment = $this->paymentService->update($payment, $request->validated());

        return new PaymentResource($payment->load(['school', 'creator']));
    }

    /**
     * Sends the receipt again - for the school that never got the first one.
     */
    public function sendReceipt(Payment $payment): JsonResource
    {
        Gate::authorize('update', $payment);

        $this->paymentService->sendReceipt($payment);

        return new PaymentResource($payment->load(['school', 'creator']));
    }

    /**
     * The same PDF the email carries, for someone who would rather just
     * download it.
     */
    public function downloadReceipt(Payment $payment, PaymentReceiptService $receipts): Response
    {
        Gate::authorize('view', $payment);

        return response($receipts->render($payment), 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="'.$receipts->fileName($payment).'"',
        ]);
    }

    public function summary(): JsonResponse
    {
        Gate::authorize('viewAny', Payment::class);

        return response()->json($this->paymentService->collectionSummary());
    }
}
