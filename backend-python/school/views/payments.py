"""Payments a school has made to the platform.

Port of PaymentController. Platform business: only a Super Admin reaches any
of it, which is why there is no SchoolScope here - a Super Admin is
unrestricted, and nobody else gets past the policy.

Not a subscription system (CLAUDE.md rule 4). This records money that
arrived; nothing here decides whether a school can use the product.

The two receipt endpoints are the reason this module waited for the M0 hosting
answer: one renders a PDF and one queues an email, and both needed the shape
of the host to be settled before they could be built.
"""

from __future__ import annotations

from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import receipts
from ..models import Payment
from ..pagination import LaravelPagination
from ..policies import PaymentPolicy, authorize
from ..requests import StorePaymentRequest, UpdatePaymentRequest
from ..resources import payment_resource
from ..services import PaymentService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        authorize(PaymentPolicy.create(request.user))

        form = StorePaymentRequest(data=request.data)
        form.is_valid(raise_exception=True)

        payment = PaymentService.create(form.validated_data, request.user)

        return Response(payment_resource(reload(payment.id)), status=status.HTTP_201_CREATED)

    authorize(PaymentPolicy.view_any(request.user))

    found = PaymentService.visible_to(
        {
            "school_id": request.query_params.get("school_id"),
            "status": request.query_params.get("status"),
            "payment_type": request.query_params.get("payment_type"),
        }
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([payment_resource(row) for row in page])


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def summary(request) -> Response:
    authorize(PaymentPolicy.view_any(request.user))

    return Response(PaymentService.collection_summary())


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, payment_id: int) -> Response:
    payment = get_object_or_404(
        Payment.objects.select_related(*PaymentService.WITH), pk=payment_id
    )

    if request.method == "PATCH":
        authorize(PaymentPolicy.update(request.user, payment))

        form = UpdatePaymentRequest(data=request.data, payment=payment)
        form.is_valid(raise_exception=True)

        PaymentService.update(payment, form.validated_data)

        return Response(payment_resource(reload(payment.id)))

    authorize(PaymentPolicy.view(request.user, payment))

    return Response(payment_resource(payment))


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def receipt(request, payment_id: int):
    payment = get_object_or_404(
        Payment.objects.select_related(*PaymentService.WITH), pk=payment_id
    )

    if request.method == "POST":
        # Sends it again - for the school that never got the first one.
        authorize(PaymentPolicy.update(request.user, payment))

        PaymentService.send_receipt(payment)

        return Response(payment_resource(payment))

    # The same PDF the email carries, for somebody who would rather just
    # download it.
    authorize(PaymentPolicy.view(request.user, payment))

    response = HttpResponse(receipts.render(payment), content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{receipts.file_name(payment)}"'

    return response


def reload(payment_id: int) -> Payment:
    return Payment.objects.select_related(*PaymentService.WITH).get(pk=payment_id)
