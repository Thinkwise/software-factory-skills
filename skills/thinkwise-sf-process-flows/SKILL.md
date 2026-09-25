---
name: thinkwise-sf-process-flows
description: Reference guide for creating and configuring process flows (and system flows) in a Thinkwise Software Factory model — the process_flow entity family, every process action type, which types can be a starting point, control-procedure-backed logic, loops, alignment, and naming conventions. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a process flow.
---

# Creating Process Flows in the Thinkwise Software Factory

A process flow is Thinkwise's mechanism for chaining tasks, reports, connectors, and decisions into
one deterministic sequence — either interactive (a user is walked through it) or, once every action
in it is non-interactive, a **system flow** that runs headless on a schedule or via API. This skill
covers the full lifecycle: the entity map, exact field-level creation steps verified against a live
model, which action types are legal starting points, naming rules, control-procedure-backed logic,
loops, layout, and translation — everything needed to build one through an MCP connector without
guessing.

Follow the connector's standard discovery→act flow; never guess entity/field/enum names — confirm
them via `get_entity_definition` first. Domain key observed in this environment:
**`sf/manage_process_flows`** **Calling an external HTTP/REST API is its own skill, not covered end-to-end here**: build the
connection and endpoint(s) via `thinkwise_sf_web_connections` (a different domain,
`sf/manage_webconnections`) first, then come back here to add the `web_connection`-type action that
calls it — see the action-type table below.

## When to use a process flow at all

Use one when the application must coordinate multiple distinct actions and their order or outcome is
meaningful — a guided user sequence, a post-action continuation, an approval/confirmation flow, an
external integration pipeline, a file pipeline, a background queue worker, a scheduled
sync/cleanup, or a reusable subflow. Don't reach for one merely because several statements happen in
sequence — that's what a task's, subroutine's, or Default/Layout/Context control procedure's own logic
already covers; see `references/process_flow_design_guide.md`'s "When to use a process flow" / "When
not to" sections before modeling the flow shell, plus the recurring user-flow and system-flow patterns,
process-procedure and process-variable design principles, subflow/transaction/error-handling/scheduling
guidance, and a final review checklist — everything below this point is the API mechanics for
whichever shape you land on.

## Plan first

Before staging anything, outline the flow in plain language and get the user's explicit
confirmation — the same propose→confirm→build discipline `thinkwise_sf_unit_tests`
and `thinkwise_sf_build_planner` already use for their own artifacts, and a concrete
instance of `thinkwise_sf_base`'s "Shared conventions" confirm-before-mutate rule
rather than a separate process invented here. Don't start "Build order" below until this step is
done.

State, in plain language — no entity names, no SQL:

- **The trigger** — what launches the flow (a task/table/report action, a schedule, a deep link, an
  API call), and which eligible-type action will sit right after `start` (see "Starting points"
  below).
- **The action sequence** — the ordered list of real steps (tasks, reports, connectors, decision
  points) and what each one is for.
- **Branch conditions** — every point where the flow diverges (Success/Not-successful/Always, a
  message-option choice, a process-procedure route) and what decides each path.
- **Loop and error handling** — any repeated section, its exit condition and iteration cap, and what
  happens on failure at each step (retry, quarantine, visible failure) — see "Branching,
  parallelism, and loops" below and the design guide's "Error handling" section for the vocabulary.

Naming (see "Naming" below) and the loop exit condition/cap (see "Branching, parallelism, and
loops" below) are two spots this often surfaces a genuine unknown rather than an obvious answer —
raise those as open questions in the outline instead of silently picking something to keep moving.

Only once the user has explicitly confirmed the outline should proceed to "Build order" and start
staging `process_flow`/`process_action` rows. If something changes mid-build — a new branch, a
different trigger — revise the outline and re-confirm rather than patching around it silently.

## Entity map

| Entity | Role | Key |
|---|---|---|
| `process_flow` | The flow itself — name, description, trigger settings | `model_id, branch_id, process_flow_id` |
| `process_action` | One node/step in the flow, typed by `process_action_type` | `model_id, branch_id, process_flow_id, process_action_id` |
| `process_step` | One connector between two actions, with its branch condition | `model_id, branch_id, process_flow_id, process_step_id` |
| `process_variable` | Flow-scoped data passed between actions | `model_id, branch_id, process_flow_id, process_variable_id` |
| `process_flow_schedule` | A recurring trigger (system flows only, practically) | `model_id, branch_id, process_flow_id, schedule_id` |
| `process_action_start_object_available` | Which task/table/report can launch the flow at a given action | `model_id, branch_id, process_flow_id, process_action_id, process_action_start_object_id` |
| `role_process_flow_overview` | Per-role security, for the whole flow or one action | — |
| `process_flow_tag` | Free-form tags | — |

`process_action`, `process_step`, and `process_flow_schedule` are **weak entities** — stage them with
`parent_entity_set: "process_flow"` and `parent_key: {model_id, branch_id, process_flow_id}`.
`process_variable` stages flat (no parent needed — its detail nav target isn't independently
addressable through this connector, so pass the full key directly).
`process_action_start_object_available` **cannot be written through this API at all**, but this
doesn't block anything in practice — see "Starting points" below for why.

**There is no dedicated "create process flow" bound task** — `process_flow` is added directly via
`stage_resource`, unlike some other object types that need a bootstrap task first.

## Build order

Actions must exist before steps can reference them; everything else has no hard ordering beyond its
own parent.

1. `process_flow` (the flow shell)
2. `process_action` rows (every node, including `start` and `stop` — if the flow should be launchable
   by a task/table/report, include that as its own eligible-type action wired directly to `start`,
   not as something wired up separately afterward — see "Starting points" below)
3. `process_step` rows (the connectors between the actions from step 2)
4. `process_variable` rows (if the flow needs to pass data between actions)
5. `process_flow_schedule` (only if this will run unattended — see [[#Schedules]])
6. Translation of anything user-facing (see "Translation" below)

## Creating the flow, its actions, and its steps

Build order is strict: **`process_flow` → `process_action` → `process_step` → `process_variable`.**
Actions are the nodes, steps are the arrows between them.

Two rules that bite:

- **A trigger object needs its own action wired right after `start`** — an `execute_task`-style
  action for the object that launches the flow must be *in* the flow, not assumed.
- **Every path must end at `stop`** — a dangling branch fails validation.

Flow and action ids share a namespace with `task`/`report` ids; query those before naming.

For the per-entity creation reference (fields, keys, the action/step wiring and the decision/branch
shapes), read `references/flow_building_blocks.md`.

## Wiring runtime values through process variables

A `process_variable` carries a value between actions. Values reach it either from an action's output
or by substitution into a later action's input, and the substitution syntax is exact.

For the full wiring reference (how each action type exposes its outputs, the substitution token form,
scope and lifetime of a variable, and the edge cases around empty/null values), read
`references/flow_variables.md`.

## Schedules and starting points

A flow is launched either by a user/object action or on a schedule, and **not every action type can
be a starting point**. There is also a hard write-API limitation on configuring some starting points.

For both (the `process_flow_schedule` entity, which action types may start a flow,
`process_action_start_object_available`, and the write-API limitation with its manual workaround),
read `references/starting_points_and_schedules.md`.

## Process action types

There are roughly 100 action types. Names are exact and easy to guess wrong, and which types are
legal inside a **system flow** differs from a normal process flow.

Check `references/action_types.md` for the full catalogue, the sys/ui legend, and which types can
serve as a starting point, **before assuming a type's exact name**. For the `show_msg` action's
message wiring specifically, see `thinkwise_sf_messages`.

## Branching, parallelism, and loops

Multiple outgoing `process_step` rows from one action fan out and run **in parallel**; a later action
that several branches converge into only fires once every parallel branch feeding it has completed.
Only one flow instance is active per user at a time.

**A loop is just a `process_step` whose `next_process_action_id` points at an action earlier in the
same flow** — nothing in the schema distinguishes a "loop" connector from any other; it's drawn (or
staged) exactly the same way, just aimed backwards. The standard shape is two pieces: the action(s)
doing repeated work, and a `decision` that tests a process variable each pass and either loops back or
lets execution continue.

Example — paging through an HTTP API until there's no more data: variables `page_number` (int,
default `1`), `has_more_pages` (bool), `iteration_count` (int, default `0`); a `web_connection` action
`get_page` (endpoint path/query string uses `{page_number}` — see
`thinkwise_sf_web_connections`); an `execute_task` action
`store_page_results` that saves the page and increments both `page_number` and `iteration_count`
(via its control procedure); a `decision` action `check_more_pages` whose `successful` step loops back
to `get_page` when `has_more_pages=true`, and whose `not_successful` step continues to `stop`.

> **Warning:** nothing in the model stops a loop from running forever — there's no built-in
> step-count fuse, and "one flow instance per user" is no protection for a system flow: a scheduled
> flow that loops without ever satisfying its exit condition keeps its Indicium worker busy
> indefinitely, and a recurring schedule can stack further runs on top if
> `multiple_running_instances_allowed` is on. **Prevention strategy:** never let the loop depend on
> the business condition alone — add an unconditional counter variable incremented every pass, AND
> the real exit condition with a hard `iteration_count < max_iterations` cap, treat hitting the cap
> as a distinct alertable outcome (set an output variable and route it to a notification/log action)
> rather than silent truncation, and prove the exit condition with a small cap in the Process flow
> monitor before raising it to a realistic ceiling.

**The exit condition and the iteration cap are business decisions, not implementation defaults** —
if the user hasn't said what business condition should end the loop or what `max_iterations`
ceiling is safe, ask rather than picking a number unilaterally, per
`thinkwise_sf_base`'s "Shared conventions" ask-don't-default rule. The "prove the
exit condition with a small cap" technique above is a testing step for validating a cap/condition
the user has already settled on — it doesn't substitute for asking what that cap/condition should
be in the first place.

## Every path must end at `stop`

Check every branch — including message/error branches and loop exits — actually reaches a `stop`
action, not just the main line. A path that dead-ends on a non-stop action leaves that flow instance
incomplete. Treat this as a mandatory check before considering any flow done, the same way you'd check
every `process_step` you added actually has a valid `next_process_action_id`.

## Process logic and control procedures

Two distinct mechanisms carry real SQL logic in a process flow, and confusing them is the most common
mistake:

1. **The action's own `use_processes` flag** ("Use process procedure") opts that specific
   `process_action` into the `PROCESSES` code group — a control procedure assigned here runs as part
   of the action itself (see "Decision as a code-only step" above for the most common use of this).
2. **The far more common pattern**: an `execute_task`/`execute_system_task` action simply calls a task
   whose own logic type is **Stored procedure**, and the *task's* control procedure (in the `TASKS`
   code group) is where the real work happens — parsing a connector's response, writing rows, etc.

Either way, creating and assigning that control procedure follows the full lifecycle documented in
`thinkwise_sf_control_procedures` — load that skill before writing the actual
SQL: check `branch_rdbms_type` first, scaffold with **Generate code group** before hand-guessing the
business-logic variables available to a `PROCESSES`/`TASKS` code-group procedure, then assign and
verify by reading the generated code, not just trusting a "successful" status.

## Alignment, naming, and translation

Flow and action ids must not collide with existing `task`/`report` ids — query those first. Canvas
`x`/`y` coordinates only affect readability, never behaviour. The flow's own description, its
actions' descriptions and any message text are translatable objects; see
`thinkwise_sf_translations`.

For the full naming convention table and the canvas-alignment guidance, read
`references/naming_and_layout.md`.

## Pre-flight checklist

- Query existing `task`/`report` ids in the target model before picking a `process_flow_id` — no
  collision is enforced automatically.
- Look at sibling process flows already in the model and match their naming convention before
  introducing a new one.
- Create `process_action` rows before any `process_step` that references them.
- Set a fresh `process_action`'s fields in **one** combined call, ordered so `process_action_type` and
  `tab_id`/`task_id` come before `process_action_id`, this lands every field correctly in
  a single round trip. Re-read the returned `fields` block on that call before moving on.
- Don't try to patch `is_system_flow` or `process_flow_platform` directly — both are
  computed/read-only.
- **A flow's trigger object (task/table/report) must be its own eligible-type `process_action` wired
  directly to `start`** — not left outside the flow. `process_action_start_object_available` can't be
  written via this API, but that's fine: it's a structural reflection of the action chain, not a
  separate switch, so no manual step in the Software Factory's own UI is needed once the trigger action
- Check every branch (including loops and error paths) actually reaches a `stop` action.
- A `duplicate_key`-style error on commit is **not a reliable signal either way** — it has been
  observed both as a false negative (the row had actually persisted) and as a real failure. Re-query
  the row after any duplicate-key error before trusting either outcome. **Confirmed cause of one such
  false negative**: adding the very first `process_action` (any type, not just `start`) to a
  brand-new, empty flow can silently auto-bootstrap a paired `start`+`stop` action set as a
  side effect — mirroring what the flow's own bound `task_add_start_stop_process_action` does —
  before your own insert commits, producing a spurious duplicate-key error even though both markers
  now exist correctly. Re-query `process_action` for the flow before adding `start`/`stop` yourself.

