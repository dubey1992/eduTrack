"""One report run across every branch in a group.

Port of App\\Support\\Reports\\GroupReport. Deliberately not one big query
over every branch: each branch has its own holiday calendar and timezone, so
"the working days in September" is a different number at each, and every
percentage is measured against that number. Running the report once per
branch and stitching the results is the only way the figures stay true.

Which also means a group total is never an average of the branches'
percentages - each report recomputes its combined rate from raw counts in
combine_totals().
"""

from __future__ import annotations


def build_group(schools, for_school, report) -> dict:
    branches = []

    for school in schools:
        built = for_school(school)
        branches.append({
            "school_id": school.id,
            "school_name": school.name,
            "range": built["range"],
            "totals": built["totals"],
            "rows": built["rows"],
            "comparison": built.get("comparison"),
        })

    group = {
        "group": True,
        "range": widest_range(branches),
        "branches": [{key: branch[key] for key in ("school_id", "school_name", "range", "totals")} for branch in branches],
        # Every row carries the branch it came from, so one flat table can be
        # read, sorted and exported without losing which school it belongs to.
        "rows": [
            {"school_id": branch["school_id"], "school_name": branch["school_name"], **row}
            for branch in branches
            for row in branch["rows"]
        ],
        "totals": report.combine_totals([branch["totals"] for branch in branches]),
    }

    # The previous period, recombined from each branch's own raw counts the
    # same way the current one is.
    if branches and all(branch["comparison"] for branch in branches):
        group["comparison"] = {
            "range": widest_range([branch["comparison"] for branch in branches]),
            "totals": report.combine_totals([branch["comparison"]["totals"] for branch in branches]),
        }

    return group


def widest_range(branches: list[dict]) -> dict:
    """The window the group as a whole covers.

    Branches can differ by a day at the edges - "up to today at the school"
    need not be the same day in two timezones. `working_days` is absent on
    purpose: it belongs to one school's calendar, and a sum across schools
    would mean nothing.
    """
    starts = [branch["range"]["from"] for branch in branches if branch["range"]["from"]]
    ends = [branch["range"]["to"] for branch in branches if branch["range"]["to"]]

    return {"from": min(starts, default=None), "to": max(ends, default=None)}
