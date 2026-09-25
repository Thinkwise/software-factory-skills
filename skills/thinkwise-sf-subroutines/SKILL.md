---
name: thinkwise-sf-subroutines
description: Reference guide for creating, configuring, calling, and maintaining subroutines (reusable SQL functions/procedures) in a Thinkwise Software Factory model, including role rights and how to call a subroutine from control procedures, views, tasks, and process flows. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a subroutine or its body SQL.
---

# Creating and Maintaining Subroutines in the Thinkwise Software Factory

Reference for the full subroutine lifecycle: `subroutine` (master object) → `subroutine_parmtr` →
`subroutine_return_col` (table returns only) → `subroutine_option` → control procedure → template →
`template_prog_object_item` → generated function/procedure, deployed to the database, called by other
business logic. The last three steps of that chain are the **general control-procedure mechanics**
already documented in `thinkwise_sf_control_procedures` — this skill covers what's
specific to subroutines (the contract, the options, choosing type/return shape, role rights, and every
place a subroutine gets *called from*) and hands the SQL-writing/assignment/generation mechanics off to
that sibling skill rather than duplicating them.

Domain key verified live: **`sf/manage_subroutines`** holds `subroutine`, `subroutine_parmtr`,
`subroutine_return_col`, `subroutine_type`, `subroutine_option`, `subroutine_type_option`,
`subroutine_type_option_value`, `subroutine_tag`, `subroutine_parmtr_tag`, and
`role_subroutine_overview.model_rights`. A different domain, `sf/manage_control_procedures`, also
exposes a `subroutine` entity set — that copy is a read-only stub (`model_id`, `branch_id`,
`subroutine_id`, `generated_by_control_proc_id` only, `allow_add/update/delete = false`) meant for
foreign-key lookups from control-procedure entities, **not** the real definition. Always create/edit
subroutines through `sf/manage_subroutines`.

## What a subroutine is, and what it isn't

A subroutine is reusable database business logic with an explicit parameter/return contract, called by
other business logic — never directly by a user-interface component. It's generated as a SQL function,
stored procedure, CLR routine, or (DB2) external routine.

| Need | Best starting concept |
|---|---|
| Reusable database calculation or operation, callable from many places | **Subroutine** |
| User explicitly starts an operation | Task, which may call a subroutine (`thinkwise_sf_tasks`) |
| Dynamic UI visibility/editability/mandatory state | Layout logic (`thinkwise_sf_control_procedures`) |
| Initial values for add/copy | Default logic (same skill) |
| Integrity around insert/update/delete | Handler or database constraint (same skill) |
| A multi-step UI or integration journey | Process flow (`thinkwise_sf_process_flows`) |
| A table-shaped subject the UI can browse/screen against | A `tab` with `type_of_table = function` (2) — **not** a subroutine, see below |
| Externally callable business operation | An API-enabled subroutine, or a dedicated web connection endpoint |

**Subroutine vs. `tab`(`type_of_table = function`) — don't conflate these.** Thinkwise has *two*
unrelated ways to model a table-valued SQL function:
- `subroutine` with `return_value = table` — a callable routine with an explicit parameter list,
  invoked from other code (`select * from dbo.get_available_resources(@date)`). No screen, no rows in
  `tab`/`col`.
- A `tab` row with `type_of_table = function` (enum: `table` 0, `view` 1, **`function` 2**, `mqt` 4,
  covered in `thinkwise_sf_views`) — a table-valued function modeled as a
  screen-viewable *subject*, with real `col` rows, references, screens, and tasks like any other table,
  generated as a function purely so it can take parameters (e.g. a date range) the way a plain view
  cannot.
Pick the `tab`-based route only when the result needs to be browsed/edited on a screen. Pick a
`subroutine` for everything else — it's lighter-weight and has no UI surface to configure.

**Subroutine vs. subflow.** A subroutine is database/business logic with a parameter and return
contract. A subflow is reusable *process-flow* orchestration (process actions and variables) — see
`thinkwise_sf_process_flows`.

## Entity map (all in `sf/manage_subroutines` unless noted)

| Entity | Key (adds to parent) | Purpose |
|---|---|---|
| `subroutine` | `subroutine_id` | Master object: type, return shape, atomic-transaction flag, API exposure |
| `subroutine_parmtr` | `subroutine_parmtr_id` | One row per input/output parameter |
| `subroutine_return_col` | `subroutine_return_col_id` | One row per column, **only when `return_value = table`** |
| `subroutine_option` | `subroutine_type_id`, `subroutine_type_option_id` | One row per enabled option (`INLINE`, `EXECUTE_AS`, …) |
| `subroutine_tag` / `subroutine_parmtr_tag` | `tag_id` | Free-form tags, same mechanism as `control_proc`'s dynamic-model tag pattern |
| `subroutine_type` *(read-only)* | `subroutine_type_id` | Platform-provided list of buildable types — **query live, don't hardcode**; varies by `branch_rdbms_type` (a PostgreSQL model only has `Function`/`Procedure`; DB2 adds `External function`/`External procedure`; SQL Server adds `CLR function`/`CLR procedure`/`DLL assembly`) |
| `subroutine_type_option` *(read-only)* | `subroutine_type_id`, `subroutine_type_option_id` | Which options exist per type, and whether each allows a custom value (`allow_custom_value`) |
| `subroutine_type_option_value` *(read-only)* | + `subroutine_type_option_value` | Allowed enumerated values for a non-custom option |
| `role_subroutine_overview.model_rights` | `role_id`, `subroutine_id` | Per-role execute grant — see "Role rights" below |

`subroutine`, `subroutine_parmtr`, and `subroutine_return_col` are all directly writable
(`allow_add/update/delete = true`) — unlike a Task (which needs `task` → `tab_task` → `task_parmtr` in a
strict order, see `thinkwise_sf_control_procedures`'s "Creating a brand-new Task"
section), a subroutine has **no chicken-and-egg gate**: create the `subroutine` row, then its
`subroutine_parmtr`/`subroutine_return_col` children, in any order, all through ordinary
`stage_resource`/`patch_resource`/`commit_resource` calls.

### `subroutine` fields

`subroutine_type_id` (must match an existing `subroutine_type` row), `return_value` (byte enum:
`none` 0, `scalar` 1, `table` 2), `return_scalar_dom_id` (domain, only for `scalar`), `return_table_id`
(a free-text label for the returned shape — **not** a foreign key to `tab`; it just names the result set
for documentation/generated-type purposes), `subroutine_description`, `single_transaction` (bool — the
"Atomic transaction" checkbox), `generation_order_no` (int — see "Generation order" below),
`alias_subroutine_id` (subroutine alias), `api` / `basic_api` (bool), `api_alias`, `new_object_status`,
`generated_by_control_proc_id`.

### `subroutine_parmtr` fields

`dom_id`, `order_no`/`abs_order_no`, `input_parmtr`/`output_parmtr` (bool, independent flags — a
parameter can be neither, though that's unusual), `alias_subroutine_parmtr_id`, `api_alias`,
`subroutine_parmtr_description`, `type_of_subroutine_parmtr_default` (byte enum: `constant_value` 0,
`null_value` 1 — only for Function/Procedure on SQL Server/DB2, per platform docs; **defaults cannot be
functions or expressions**), `default_value`.

### `subroutine_return_col` fields

`dom_id`, `primary_key` (bool), `mand` (bool), `order_no`/`abs_order_no`. Define every column with a
real domain and correct nullability — a table-valued function should behave relationally.

## Choosing the subroutine type

Query `subroutine_type` for the model first — the buildable set is platform-dependent, not fixed. Then
pick by *behavior*, not availability:

| Type | Use when |
|---|---|
| **Function** | The operation conceptually returns a value with no externally visible state change — calculation, normalization, lookup, or a queryable table/range. Composable in `select`/`join`/`where`/computed columns, but a scalar function evaluated once per row can be expensive at scale — prefer set-based logic or a joinable view for bulk use. |
| **Procedure** | Commands, state changes, integration operations, multi-step work. Harder to compose inside a query; make side effects explicit in the name. |
| **CLR function / CLR procedure** *(SQL Server)* | Only when native SQL genuinely can't implement the requirement and the assembly-deployment/permission-set cost is justified (a specialist library, a legacy integration). New Indicium connectors/process actions are usually easier to operate than database CLR for external integration. |
| **DLL assembly** *(SQL Server)* | The assembly registration backing a CLR function/procedure's `DLL Assembly` option — infrastructure, not business logic itself. |
| **External function / External procedure** *(DB2)* | References an external program — treat as an infrastructure dependency with explicit ownership/deployment/rollback documentation. |

## Choosing the return shape (`return_value`)

- **None (0)** — commands where success/failure and optional output parameters suffice (recalculation,
  sync, cleanup, state transition). Don't hide a useful outcome behind "no return" — a caller often
  needs an inserted id, a row count, or a status; use output parameters for those.
- **Scalar (1)** — exactly one conceptual value: boolean decision, amount, code, date, single id. Pick
  `return_scalar_dom_id` for its real semantics, not just a datatype match — a generic "returns text for
  everything" scalar weakens validation and API metadata.
- **Table (2)** — zero-to-many rows with a stable schema (availability candidates, date ranges,
  validation findings, search results). Define every `subroutine_return_col` with a real domain,
  sequence, nullability, and key where applicable; avoid hidden state changes or row-order assumptions.
- If the request doesn't clearly imply which shape the caller actually needs — e.g. it's ambiguous
  whether a created id/status matters to the caller, or whether a single row vs. many rows is
  expected — ask the user rather than picking from the list above unilaterally
  (`thinkwise_sf_base`'s "Ask, don't default").

## Subroutine options — verified per type (SQL Server model)

Options live on `subroutine_option`, keyed by `(subroutine_id, subroutine_type_id,
subroutine_type_option_id)`. Query `subroutine_type_option` for the target `subroutine_type_id` to get
the live set for the model in hand — the table below is what one SQL Server model exposed, to show the
shape, not a universal list:

| `subroutine_type_id` | `subroutine_type_option_id` | `allow_custom_value` | Values / meaning |
|---|---|---|---|
| Function | `INLINE` | No | `OFF` / `ON` — marks a scalar function inlinable; improves query performance, has usage restrictions |
| Function | `RETURNS_NULL_ON_NULL_INPUT` | No | `No` / `Yes` — skip execution when any input is null; only correct when null propagation is guaranteed for *every* parameter (wrong if null means "use default"/"unbounded"/"not provided") |
| Function | `SCHEMABINDING` | No | `No` / `Yes` — locks referenced-object schema, enables optimizations, constrains future changes to those objects |
| Function, Procedure, CLR function, CLR procedure | `EXECUTE_AS` | Yes (`custom_value` = the account) | Defined privilege boundary only — least-privilege principal, document why elevation is needed |
| CLR function | `RETURNS_NULL_ON_NULL_INPUT` | No | Same semantics as above |
| CLR function, CLR procedure | `DLL Assembly` | Yes (`custom_value` = assembly id) | Which registered `DLL assembly` subroutine backs this CLR routine |
| DLL assembly | `Assembly id` / `DLL file location` | Yes | Free text |
| DLL assembly | `Permission set` | No | `SAFE` / `EXTERNAL_ACCESS` / `UNSAFE` — progressively wider capability and risk; `UNSAFE`/external-access should need explicit architecture/security approval |

To set a non-custom option: add a `subroutine_option` row with `subroutine_type_option_value` set to one
of the values from `subroutine_type_option_value` for that `(subroutine_type_id,
subroutine_type_option_id)`. To set a custom-value option (`EXECUTE_AS`, `DLL Assembly`, `Assembly id`,
`DLL file location`): set `custom_value` instead, leave `subroutine_type_option_value` unset.

DB2 also exposes `DETERMINISTIC` and `MODIFIES SQL DATA` booleans for functions — these must accurately
describe behavior; wrong determinism metadata can lead to invalid optimizer assumptions.

## Plan first

Apply `thinkwise_sf_base`'s "Shared conventions" **Confirm-before-mutate** rule
here: before the first `stage_resource` call, state the proposed contract in plain language and get
the user's explicit confirmation — don't create any row first and adjust after the fact. For a
subroutine, that contract is:

- **Subroutine type** (Function, Procedure, CLR function/procedure, …) — see "Choosing the
  subroutine type" below.
- **Return shape** (`none`/`scalar`/`table`) — and, if scalar, the domain; if table, the column
  list — see "Choosing the return shape" below.
- **Parameters** — name, direction (input/output), and domain for each — see "Parameter design"
  below.
- **`single_transaction`** setting — see "Transaction behavior" below.
- **API exposure** — confirmed off unless the user has actually asked for it — see "Publishing as
  an API" below.

Only start staging `subroutine`/`subroutine_parmtr`/`subroutine_return_col` rows once the user has
confirmed this contract.

## Creating a subroutine

The generated object's name is the bare `subroutine_id`. Its body is a control-procedure template in
the `PROCEDURES`/`FUNCTIONS`/`TABLE_VALUED_FUNCTIONS` code group, generated the same two-task way as
any other control procedure.

**Known gap:** a brand-new *standalone* subroutine (no table/view/task to hang off) may never get its
`prog_object` placeholder materialized through the API — author it fully, then treat the generate as
a manual Software Factory step and say so.

**Role rights are required for a caller to execute it** — a missing right fails at runtime, not at
generation.

For the step-by-step, the per-type option matrix, and the role-rights entities, read
`references/creating_a_subroutine.md`.

## Calling a subroutine

A subroutine is callable from a control procedure template, a view's SELECT, a task's logic, and a
process flow action — and the call syntax differs per context and per RDBMS dialect. The generated
object's name is the bare `subroutine_id`.

**Role rights are required for a caller to execute it** (see above) — a missing right fails at
runtime, not at generation.

For the call form in each context, read `references/calling_a_subroutine.md`.

## Design and operational concerns

Once a subroutine works, a second set of decisions governs how it behaves in production:
transactions, the error contract, API exposure, authorization, parameter design, performance,
coupling, versioning, and testing.

For all of it (`single_transaction` semantics and when to turn it off, what a subroutine may raise
and how callers see it, publishing as an API endpoint, the execution-context/authorization model,
parameter-design rules, performance traps, avoiding hidden coupling between callers, and how to
version a subroutine whose signature changes), read `references/design_and_operations.md`.

## Practical examples and common failure patterns

`references/practical_examples.md` has worked examples across the pattern families that recur in mature
models (calculation/derivation, validation/eligibility, availability/overlap, date/period helpers,
integration subroutines, platform/user helpers), each with a concrete parameter/return sketch — read it
for inspiration before designing a new subroutine from scratch. The same file's closing checklist lists
the failure patterns to watch for (procedure-used-as-function, scalar-per-row-at-scale,
output-parameter-explosion, and the rest).

## Pre-flight checklist

- Create through `sf/manage_subroutines`, not the read-only `subroutine` stub in
  `sf/manage_control_procedures`.
- `return_table_id` is a free-text label, not a `tab` foreign key — don't go looking for it in the data
  model.
- No creation-order gate like Task's `task`→`tab_task`→`task_parmtr` chain — `subroutine`,
  `subroutine_parmtr`, `subroutine_return_col` are all directly writable in any order.
- Grant role execute rights (`role_subroutine_overview.model_rights`, flip `granted`) — a clean
  generation status proves nothing about who can call the routine.
- Write the body by following `thinkwise_sf_control_procedures` end to end:
  `FUNCTIONS`/`TABLE_VALUED_FUNCTIONS`/`PROCEDURES` code group, `func_`/`proc_` `prog_object_id` prefix,
  bare `subroutine_id` as the real generated object name, Static assignment,
  `program_object_item`/`control_proc_type = 1`.
- A brand-new *standalone* subroutine's `prog_object` placeholder may not materialize through
  `task_generate_code_grp` — verified gap; be ready to say a manual Software Factory generate pass is
  needed, rather than retrying alternate API paths indefinitely.
- Set `generation_order_no` so a subroutine that calls another subroutine (especially function-calls-
  function) generates after its dependency — functions don't get SQL Server's deferred-name-resolution
  leniency that procedures do.
- There is no dedicated process-action type for calling a subroutine — it's always via a `decision`
  action's `PROCESSES` control procedure or a task's `TASKS` control procedure.

