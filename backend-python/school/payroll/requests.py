"""What each payroll form must hold before anything is saved.

Every failure is reported at once, field by field, in the envelope every
other form uses. Money is Decimal throughout (school/requests.py MoneyField),
and never more than the DECIMAL(12,2) column holds.
"""

from __future__ import annotations

import decimal

from rest_framework import serializers

from ..enums import PayComponentType, PaymentMode
from ..requests import MoneyField, ScopedSerializer
from ..validation import (
    LaravelCharField,
    LaravelDateField,
    LaravelIntegerField,
    at_most,
    normalise,
    optional_text,
    required,
    selected_is_invalid,
)

# The most a DECIMAL(12,2) holds.
MAX_AMOUNT = decimal.Decimal("9999999999.99")
MAX_COMPONENTS = 30


def check_amount(field: str, value, errors: dict) -> None:
    if value is not None and value > MAX_AMOUNT:
        errors.setdefault(field, []).append(at_most(field, "9,999,999,999.99"))


class SaveSalaryRequest(serializers.Serializer):
    """A whole salary: the basic and every component, replacing what was there.

    Components arrive as a list and are checked here rather than by a nested
    serializer, so a mistake in the fourth component reads as
    `components.3.amount` - where the screen can put it.
    """

    basic_salary = MoneyField("basic salary", error_messages={"required": required("basic_salary")})

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    def to_internal_value(self, data):
        """The basic and the components are checked together, so a bad basic
        never hides a bad component - DRF alone would stop at the first."""
        errors: dict[str, list[str]] = {}

        try:
            attrs = super().to_internal_value(data)
        except serializers.ValidationError as failure:
            errors.update({key: list(value) for key, value in failure.detail.items()})
            attrs = {}

        check_amount("basic_salary", attrs.get("basic_salary"), errors)

        raw = self.initial_data.get("components", [])

        if raw is None:
            raw = []

        if not isinstance(raw, list):
            raise serializers.ValidationError({"components": ["The components must be a list."]})

        if len(raw) > MAX_COMPONENTS:
            errors["components"] = [f"A salary can have at most {MAX_COMPONENTS} components."]

        components, seen = [], set()

        for index, item in enumerate(raw):
            prefix = f"components.{index}"
            item = item if isinstance(item, dict) else {}
            type_ = item.get("type")
            name = (item.get("name") or "").strip() if isinstance(item.get("name"), str) else ""

            if type_ not in PayComponentType.values:
                errors[f"{prefix}.type"] = [selected_is_invalid("type")]

            if not name:
                errors[f"{prefix}.name"] = [required("name")]
            elif len(name) > 100:
                errors[f"{prefix}.name"] = ["The name field must not be greater than 100 characters."]
            elif (type_, name.lower()) in seen:
                errors[f"{prefix}.name"] = [f'"{name}" appears twice as {"an earning" if type_ == "earning" else "a deduction"}.']

            seen.add((type_, name.lower()))

            try:
                amount = MoneyField("amount").to_internal_value(item.get("amount"))
            except serializers.ValidationError as failure:
                errors[f"{prefix}.amount"] = list(failure.detail)
                amount = None

            if amount is None and f"{prefix}.amount" not in errors:
                errors[f"{prefix}.amount"] = [required("amount")]

            check_amount(f"{prefix}.amount", amount, errors)
            components.append({"type": type_, "name": name, "amount": amount})

        if errors:
            raise serializers.ValidationError(errors)

        attrs["components"] = components

        return attrs


class GeneratePayrollRunRequest(ScopedSerializer):
    """A month for a school. The school is the actor's own unless they span
    several, when they name it - see ScopedSerializer."""

    year = LaravelIntegerField("year", min_value=2000, max_value=2100)
    month = LaravelIntegerField("month", min_value=1, max_value=12)

    def __init__(self, *args, school_today=None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.school_today = school_today

    def validate(self, attrs):
        self.validate_school_id_field()

        today = self.school_today(self.resolved_school_id())

        # Not a month that has not started: nobody has worked it yet.
        if (attrs["year"], attrs["month"]) > (today.year, today.month):
            raise serializers.ValidationError({"month": ["Payroll cannot be run for a month that has not started."]})

        return attrs


class AdjustmentRequest(serializers.Serializer):
    type = LaravelCharField("type", max_length=16)
    name = LaravelCharField("name", max_length=100)
    amount = MoneyField("amount", minimum="0.01", error_messages={"required": required("amount")})
    note = LaravelCharField("note", max_length=255)

    def __init__(self, *args, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)

    # Field by field, so an unknown type is reported beside a missing name
    # rather than only once the name is fixed.
    def validate_type(self, value):
        if value not in PayComponentType.values:
            raise serializers.ValidationError(selected_is_invalid("type"))

        return value

    def validate_amount(self, value):
        errors: dict[str, list[str]] = {}
        check_amount("amount", value, errors)

        if errors:
            raise serializers.ValidationError(errors["amount"])

        return value


class PayRequest(serializers.Serializer):
    """When and how pay left the school. Not a date in the future - payment
    that has not happened is not recorded as made."""

    paid_on = LaravelDateField("paid_on")
    payment_mode = LaravelCharField("payment_mode", max_length=32)
    payment_reference = optional_text("payment_reference", 100)

    def __init__(self, *args, school_today=None, **kwargs) -> None:
        if "data" in kwargs:
            kwargs["data"] = normalise(kwargs["data"])

        super().__init__(*args, **kwargs)
        self.school_today = school_today

    def validate(self, attrs):
        errors: dict[str, list[str]] = {}

        if attrs["payment_mode"] not in PaymentMode.values:
            errors["payment_mode"] = [selected_is_invalid("payment_mode")]

        if self.school_today is not None and attrs["paid_on"] > self.school_today:
            errors["paid_on"] = ["The payment date cannot be in the future."]

        if errors:
            raise serializers.ValidationError(errors)

        return attrs
