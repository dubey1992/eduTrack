"""An amount in words, for the line under a receipt's total (docs/fees.md, F3):
"Indian Rupees Two Thousand Five Hundred and Fifty Paise Only".

English, the international scale (thousand, million, billion), up to
9,999,999,999.99 - the most a DECIMAL(12,2) holds. The currency's name comes
from a short table of the codes schools use; any other code is printed as
itself, with "Hundredths" for the minor unit, rather than guessed at.
"""

from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal

# ISO 4217 code -> (major unit, minor unit), plural as a receipt reads them.
CURRENCIES: dict[str, tuple[str, str]] = {
    "INR": ("Indian Rupees", "Paise"),
    "USD": ("US Dollars", "Cents"),
    "EUR": ("Euros", "Cents"),
    "GBP": ("Pounds Sterling", "Pence"),
    "NGN": ("Nigerian Naira", "Kobo"),
    "KES": ("Kenyan Shillings", "Cents"),
    "UGX": ("Ugandan Shillings", "Cents"),
    "TZS": ("Tanzanian Shillings", "Cents"),
    "GHS": ("Ghanaian Cedis", "Pesewas"),
    "ZAR": ("South African Rand", "Cents"),
    "AED": ("UAE Dirhams", "Fils"),
    "SAR": ("Saudi Riyals", "Halalas"),
    "QAR": ("Qatari Riyals", "Dirhams"),
    "OMR": ("Omani Rials", "Baisa"),
    "PKR": ("Pakistani Rupees", "Paisa"),
    "BDT": ("Bangladeshi Taka", "Poisha"),
    "NPR": ("Nepalese Rupees", "Paisa"),
    "LKR": ("Sri Lankan Rupees", "Cents"),
    "AUD": ("Australian Dollars", "Cents"),
    "CAD": ("Canadian Dollars", "Cents"),
    "NZD": ("New Zealand Dollars", "Cents"),
    "SGD": ("Singapore Dollars", "Cents"),
    "MYR": ("Malaysian Ringgit", "Sen"),
}

ONES = (
    "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
    "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
)
TENS = ("", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety")
SCALES = ((1_000_000_000, "Billion"), (1_000_000, "Million"), (1_000, "Thousand"))
LIMIT = Decimal("9999999999.99")


def below_thousand(n: int) -> str:
    parts: list[str] = []

    if n >= 100:
        parts.append(f"{ONES[n // 100]} Hundred")
        n %= 100

    if n >= 20:
        parts.append(TENS[n // 10] + (f"-{ONES[n % 10]}" if n % 10 else ""))
    elif n:
        parts.append(ONES[n])

    return " ".join(parts)


def integer_words(n: int) -> str:
    """1234567 -> "One Million Two Hundred Thirty-Four Thousand Five Hundred
    Sixty-Seven"."""
    if n == 0:
        return "Zero"

    parts: list[str] = []

    for size, name in SCALES:
        if n >= size:
            parts.append(f"{below_thousand(n // size)} {name}")
            n %= size

    if n:
        parts.append(below_thousand(n))

    return " ".join(parts)


def currency_names(code: str) -> tuple[str, str]:
    return CURRENCIES.get((code or "").upper(), (code or "", "Hundredths"))


def amount_in_words(value, currency_code: str) -> str:
    """"Indian Rupees Two Thousand Only", "US Dollars Twelve and Fifty Cents
    Only". Raises ValueError outside 0 to 9,999,999,999.99."""
    amount = Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    if amount < 0 or amount > LIMIT:
        raise ValueError(f"{amount} is outside what a receipt can hold")

    major, minor = currency_names(currency_code)
    whole = int(amount)
    hundredths = int((amount - whole) * 100)

    words = f"{major} {integer_words(whole)}"

    if hundredths:
        words += f" and {integer_words(hundredths)} {minor}"

    return f"{words} Only"
