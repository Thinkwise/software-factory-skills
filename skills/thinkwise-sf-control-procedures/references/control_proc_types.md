# Static vs SQL-typed control procedures, generation strategies, and control_proc_type

Loaded on demand from `thinkwise_sf_control_procedures`.

## Static vs. SQL-typed control procedures

Every control procedure has an assignment field: **Static** (`assign_type = 0`) or **SQL**
(`assign_type = 2`).
- **Static** — pick program objects by hand, fill in `[PARMTR]` values per assignment row on the
  Assigning tab. Simple, explicit, but every new table/task needs a manual assignment. Use for
  one-off, non-repeating logic.
- **SQL (dynamic)** — a query in the control procedure decides which objects get the template and
  what each `[PARMTR]` resolves to, including duplicating a row per parameter value. Assignments
  follow automatically as the model changes. Use the moment the same template needs to apply to
  many objects, or needs to track model changes over time. Reserved in framework code for built-in
  procedures, but perfectly valid for custom logic once a pattern repeats.

Switching direction later is mechanical, not a merge: static→dynamic converts existing rows into
control-procedure code; dynamic→static materializes the query's current result as static rows.
**If it's not obvious which to start with, ask the user rather than picking one** — lay out the
trade-off (Static: explicit, one manual assignment per object, easy to reason about, more upkeep
as objects multiply; SQL: automatic fan-out that tracks model changes, but the assignment logic
itself becomes something to write and maintain) and let them choose, per "Ask, don't default" in
`thinkwise_sf_base`'s "Shared conventions."

### Generation strategies (SQL-typed only)
The `control_proc.strategy` enum: `delete` (0), `fully_managed` (1), `managed_via_staging_table` (2).
Docs/blog inconsistently call `fully_managed` both "Fully managed" and "Fully controlled" — same
thing.

| Strategy | Behavior | Use when |
|---|---|---|
| `delete` | Drops every previously-generated object, recreates all from scratch each run | Rarely — costs IO, risks referential-integrity errors on interdependent objects |
| `fully_managed` | Nothing auto-deleted; your SQL inserts/updates/deletes rows itself | Objects reference each other in ways the Staged diff can't resolve |
| `managed_via_staging_table` ("Staged") | Populate `#`-prefixed staging tables with desired end state; the Software Factory diffs and inserts/updates/deletes only what changed | **Default choice** for new SQL-typed procedures. Static-typed procedures always behave this way. Identities, trace columns, and calculated fields aren't settable in staging tables. |

### `control_proc_type` — separating custom logic from generated infrastructure

A separate field from `assign_type` above: `control_proc.control_proc_type` (Byte enum) marks *what
kind of control procedure this row is*, not how it's assigned. Confirmed live values:
`program_object` (`0`), `program_object_item` (`1`), `meta_definition` (`2`).

- **`program_object_item` (`1`) is hand-written logic for one specific object** — this is the actual
  custom business logic a developer wrote (e.g. "default this one column to now").
- **`program_object` (`0`) and `meta_definition` (`2`) are shared generators and framework
  infrastructure** — meta-programming control procedures that produce boilerplate for many objects at
  once (including the framework's own smoke-test/upgrade/unit-test-scaffolding machinery), or the
  wrapper templates (`_start`/`_end`) that bookend generated code. They aren't application logic
  themselves even though many generated `prog_object` rows point at them.

**When scoping "what custom logic exists to review/test/document," filter `control_proc` by
`control_proc_type eq 1` directly rather than enumerating generated `prog_object` rows for a code
type** — scanning generated objects first (e.g. "every table with a Default enabled") overcounts
wildly, since dozens of tables can share one generic generator while only a couple actually have
`program_object_item` overrides. This complements, rather than replaces, the "misleading
`control_proc_id`" reading in "Actually generating code" below — that section is for confirming which
control procedure produced an *already-generated* code section by reading its header comments;
filtering on `control_proc_type` is the faster first pass for finding candidates before you get there.

**Setting `assign_type`/`control_proc_type` when creating a `control_proc` row**: pass the enum's raw
numeric code (e.g. `0`, `1`), not its display label (`static`, `program_object_item`) — a label string
is rejected with an invalid-value error even though the same field defaults correctly to its numeric
form when left unset. If a combined add reports these fields as not-applied, a follow-up edit setting
them by numeric code resolves it.
