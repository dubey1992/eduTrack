# Multi-branch schools

**Status: built.** Steps 1-4 of the phasing below have landed; step 5 is
partly done (the group dashboard exists; per-branch report breakdowns do
not). Decisions were taken on 2026-09-15.

A school group runs several branches — St Mary's North, South and East — under
one name. Today eduTrack has no idea they are related: each is an unconnected
school, and nobody can see the group as a whole.

## The decision that makes this small

**A branch is a school row with a parent.**

```
schools
  id
  parent_school_id   <- NEW: nullable, self-referencing, null for a standalone school
  name, address, currency_code, timezone, status …

St Mary's Group          parent
 ├─ St Mary's North       branch
 ├─ St Mary's South       branch
 └─ St Mary's East        branch
```

A branch already needs everything a school row holds: its own address, its own
currency (branches can be in different countries), its own timezone, its own
academic years, classes, staff, students and payments. It *is* a school. Saying
so costs one nullable column.

The alternative — a `branches` table and a `branch_id` on every tenant table —
was rejected. There are **28 tables carrying `school_id`**, and every policy,
service, form request and test that scopes by it would have to learn a second
dimension that means the same thing. That is a rewrite of the tenancy model to
express a relationship one column already expresses.

### What this buys immediately

Nothing in those 28 tables changes. `school_id` still points at the branch that
owns the record, isolation still works exactly as it does today, and every
existing test still asserts the right thing. A group is a query, not a new
concept in the data.

## The actual work: one seam, not 154 edits

This is the part to get right, and it is most of the effort.

`Group Admin` needs to read across several schools. Today "which schools may
this actor touch?" is answered inline, in two shapes, in **154 places**:

```php
// policies (24 of them)
return $actor->role === UserRole::SuperAdmin || $actor->school_id === $subject->school_id;

// services (38 files)
->when($actor->role !== UserRole::SuperAdmin,
    fn ($query) => $query->where('school_id', $actor->school_id))

// form requests (12 files)
$this->user()->role === UserRole::SuperAdmin ? $this->integer('school_id') : $this->user()->school_id
```

Adding a third role to 154 branching points by hand is how this feature would
introduce an isolation bug. **Introduce a scope object first**, and let each
call site ask it instead of asking the role:

```php
final class SchoolScope
{
    public static function for(User $actor): self;

    public function allows(?int $schoolId): bool;      // replaces the === comparison
    public function applyTo(Builder $query, string $column = 'school_id'): Builder;
    public function writableSchoolId(?int $requested): int;  // replaces resolvedSchoolId()
    public function ids(): ?array;                     // null = every school
}
```

Then the three roles are three ways of building one object:

| Actor | Scope |
|---|---|
| `SUPER_ADMIN` | unrestricted |
| `GROUP_ADMIN` | their parent school plus its children |
| everybody else | their own `school_id`, exactly as today |

Once every call site goes through `SchoolScope`, Group Admin is a change to
*one* class. Every later phase inherits it, which is why this should land
before Payroll rather than after.

**Do this as its own step, with the existing tests green and no behaviour
change**, before `GROUP_ADMIN` exists at all. A refactor that changes nothing
is reviewable; a refactor tangled with a new role is not.

## Group Admin

A new `UserRole::GroupAdmin`, attached to the parent school.

- **Reads** every branch beneath its parent — students, staff, attendance,
  reports, payments.
- **Writes** inside a branch it names explicitly, never "the group". There is
  no such thing as a student belonging to a group.
- **Cannot** create or delete schools, or move a branch between groups. That
  stays `SUPER_ADMIN` — it is a platform-shape change, not a school operation.
- **Cannot** reach a school outside its own group, under any request.

`SCHOOL_ADMIN` keeps meaning precisely what it means today: one school, one
boundary. That is deliberate — no existing permission changes meaning, so no
existing isolation test has to be re-read.

### Tests this needs

Per CLAUDE.md rule 15, every permission needs an ALLOW and a DENY. The ones
that matter most here:

- A Group Admin reads a sister branch's students. **ALLOW**
- A Group Admin reads a school in *another* group. **DENY**
- A Group Admin writes to a sister branch by naming it. **ALLOW**
- A Group Admin creates a school. **DENY**
- A School Admin at a parent reads a child branch. **DENY** — this is the
  regression the "parent sees all" option would have introduced, and the test
  exists to keep it impossible.
- A School Admin at a branch reads its parent. **DENY**

## What stays per-branch

Academic years, departments, subjects, classes and sections, holidays,
timetables, staff, students, transport, payments. All of it, unchanged.

Branches run their own calendars because real groups do — a city holiday at
North is not a holiday at South, and term dates differ. The cost is that the
same subject list gets created once per branch; the bulk CSV import
(`docs/imports.md`) already makes that a two-minute job per branch.

Nothing inherits from the parent. There is no "mine, else my parent's" lookup
anywhere, which keeps every existing query exactly as it is.

## Staff belong to one branch

A user has one `school_id`, as today. Somebody genuinely working at two
branches gets two accounts.

This is the decision that keeps the auth model intact. The alternative — a
`school_user` pivot and a "acting as branch X" session — means every request
must establish which branch the actor is currently in, and every policy must
verify membership of it. That is a far larger change to the part of the system
it is least safe to get wrong.

**Known cost, accept it knowingly:** `users.email` is globally unique, so the
second account needs a second address. If a group later says that is
unacceptable, revisit it as its own piece of work, not as a corner of this one.

## Money and reporting across a group

Payments stay recorded against the branch that paid, in that branch's currency
— `payments.currency_code` already snapshots it.

Group totals **group by currency and never blend** (CLAUDE.md rule 5). A group
with branches in India and Nigeria reports "₹4,50,000 INR + ₦2,100,000 NGN",
never a single converted number. The existing Super Admin payment summary
already does this; the group view is the same query with a different scope.

### Reporting on a whole group

All four reports do this. A Group Admin who names no branch gets the group;
one who names a branch gets that branch alone. A Super Admin still names a
school - "every school on the platform" is not a report.

It runs the existing report **once per branch** rather than as one query with
a `whereIn`, because every branch has its own holiday calendar and its own
timezone. "The working days in September" is a different number at each of
them, and every percentage in a report is measured against that number.

Which also settles the group total: it can never be an average of the
branches' percentages, or a branch of forty would weigh the same as a branch
of four hundred. The combined rate is recomputed from raw counts, and each
report does that arithmetic itself (`App\Support\Reports\CombinesTotals`) -
a generic "sum the integers and guess at the rates" helper would be quietly
wrong, since a student attendance rate and a teaching coverage rate are not
the same shape.

The group range deliberately carries no `working_days`: adding two schools'
calendars together is a number that means nothing. Each branch reports its
own, in the breakdown.

A group CSV gains a leading **School** column, so the rows are not a heap.

## What landed, in order

1. **`SchoolScope`, no behaviour change.** ✅ The 154 call sites route through
   it. 735 tests green before and after, none edited — that was the proof.
2. **`parent_school_id`.** ✅ Migration, `parent`/`branches` relationships,
   `groupSchoolIds()`, and the one-level validation.
3. **`GROUP_ADMIN`.** ✅ The role, its scope, the capability changes, and 34
   ALLOW/DENY tests.
4. **The group in the UI.** ✅ The filter reads "Filter by branch" / "Whole
   group" for a Group Admin, the school form has a parent picker that refuses
   to offer an impossible parent, and the school list shows the hierarchy.
5. **Group dashboards and reports.** ✅ The group dashboard rolls up its
   branches, and all four reports break down by branch when no branch is
   named.

### Two things the refactor caught

Worth recording, because they are exactly what step 1 existed to prevent.
Sweeping the `SuperAdmin` call sites left two scope decisions keyed on
`SchoolAdmin` instead:

- **`UserService::paginate`** was role-gated, not scoped. A Group Admin would
  have seen every user account on the platform.
- **`DashboardService`** dispatched on a `match ($actor->role)` with no arm
  for the new role — an `UnhandledMatchError`, not a default.

Both are covered by tests now. Neither would have been found by adding the
role to 154 branching points by hand.

## Where a Group Admin's limits are enforced

- **Scope** (which schools): `App\Support\SchoolScope`. A Group Admin
  resolves to `School::groupSchoolIds()` - the parent and its branches.
- **Capability** (what they may do): `UserRole::administersSchool()`, which is
  true for a School Admin and a Group Admin alike, plus the `ADMIN_ROLES`
  constants on each policy. `SchoolPolicy` and `PaymentPolicy` deliberately
  do not mention it.
- **Which branch a write lands in**: `SchoolScope::writableSchoolId()`, and
  `ScopesSchool::schoolIdRules()` makes `school_id` required for anybody whose
  scope covers more than one school.

## Deliberately out of scope

- **More than one level.** Groups of groups. One level of parent is what
  schools actually have; arbitrary depth costs recursive queries everywhere and
  buys nothing anyone has asked for. Enforce it in validation so the data
  cannot quietly become a tree.
- **Moving a student between branches.** A transfer is not an edit — it has to
  carry or close attendance history, leave balances and transport assignments.
  Worth its own design. Until then: deactivate at one branch, admit at the
  other.
- **Sharing a user across branches.** See above.
- **Group-level billing.** Payments are per branch; a group invoice is a
  reporting question, not a new record type.

## Risks worth naming now

- **The refactor is the risk, not the feature.** 154 call sites, each one a
  place where a mistake means one school reading another's data. Step 1 must
  land alone, with every existing isolation test green and no new ones needed
  to make it pass.
- **`GROUP_ADMIN` in `AppNav`.** The sidebar and the route guard share one
  config, so the new role must be added there deliberately or it gets either
  too much or too little of the menu.
- **Seeders and factories** assume a flat world. `parent_school_id` defaults to
  null, so they keep working — but the group tests need a factory state that
  builds a parent with branches.
- **Nothing here is reversible cheaply once schools are linked in production.**
  Getting the "one level only" rule in at step 2 matters more than it looks.
