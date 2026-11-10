# Creating process flows, actions, steps, and variables

Loaded on demand from `thinkwise-sf-process-flows`.

## Creating `process_flow`

Minimal valid row: `{model_id, branch_id, process_flow_id}` — everything else defaults.

- Mandatory: `model_id`, `branch_id`, `process_flow_id`, plus these which are pre-filled with sane
  defaults so you rarely need to touch them: `use_starting_points` (default `true`),
  `use_api_trigger` (default `true`, hidden field), `custom_protocol` (default `false`),
  `deep_link_allowed` (default `false`), `multiple_running_instances_allowed` (hidden, default
  `false`), `iam_custom_schedule_allowed` (hidden, default `false`).
- Optional: `process_flow_description`, `alias_process_flow_id` (hidden), `custom_protocol_alias`
  (hidden).
- **`process_flow_platform` is read-only** — auto-derived, not settable at creation.
- **`is_system_flow` is hidden and never set directly** — it's computed: the flow becomes a system
  flow automatically the instant every `process_action` in it is a non-interactive type (see the
  `system_flow_action` flag in `references/action_types.md`). Don't try to patch this field — add a
  non-interactive action instead if the flow needs to qualify.

## Creating `process_action`

`start` (type 98, x 5) and `stop` (type 99, x 100) already exist: the Software Factory creates them as
soon as the `process_flow` is committed (verified through the write API on SF 2026.2). Don't add them
and don't run `task_add_start_stop_process_action`.

Always mandatory, regardless of type: `model_id`, `branch_id`, `process_flow_id`, `process_action_id`,
`process_action_type`, `use_processes`, `confirm_start`, `auto_confirm`, `process_action_mand`.

`x_coordinate` / `y_coordinate` / `width` / `height` are editable but **never mandatory** — safe to
omit; set them later for layout (see "Alignment" below).

Per-type FK requirements (confirmed by patching `process_action_type` and re-reading field states —
check `references/action_types.md` for the full ~100-value catalog before assuming a type's exact
name):

| `process_action_type` | Extra mandatory fields | Notes |
|---|---|---|
| `start` (98) | none | Pure marker; `use_processes` itself becomes hidden for this type |
| `stop` (99) | none | Pure marker |
| `execute_task` (60) | `task_id` (mandatory) | `task_variant_id` optional |
| `execute_tab_task` (6) | `tab_id` (mandatory), `tab_task_id` (mandatory) | `tab_variant_id` stays hidden/optional until `tab_id` is set |
| `activate_detail` (1) | `tab_id` (mandatory), `ref_id` (mandatory) | **`tab_id` must be the detail/target table of the reference** (the ref's `target_tab_id`), not the source/context table — setting `tab_id` to the source table makes `ref_id` reject writes. Does **not** open as a popup/modal; it activates a detail inline in the current screen tree — see `open_document` below for a modal |
| `open_document` (2) | `tab_id` (mandatory) | `tab_variant_id` optional; `ref_id` hidden/unused. The actual modal-popup mechanism — see "Wiring runtime values through process variables" below for the fixed-input parameter that makes it open floating/modal |
| `change_filter` (330) | `tab_id` (mandatory) | The filter condition itself is **not** a plain field — see "Wiring runtime values through process variables" below |
| `web_connection` (602) | `web_connection_id` (mandatory), `web_connection_endpoint_id` (mandatory) | **The preferred choice for any HTTP/REST call — build the connection and its endpoint(s) first**, via `thinkwise-sf-web-connections`; the connection carries full configuration (base URL, auth, method, path, body, headers, output parsing) and is fully buildable through the API. (Indicium · split-domain) Build it in `sf/manage_webconnections` — `sf/manage_process_flows` shows the connection only as a reference, with almost nothing writable. Once the connection exists, map this action's inputs by editing the pre-seeded `process_action_modeler_web_connection_endpoint_input` rows (which creates the stored `process_action_web_connection_endpoint_parmtr_input_parmtr` rows; connection-level inputs land in `process_action_web_connection_parmtr_input_parmtr`) and its outputs on the `process_action_modeler_web_connection_endpoint_output` rows — see that skill for the full field/enum reference and worked examples. The domain also exposes a bound migration task on this action, `task_enrichment_conv_http_connector_to_web_connection`, for converting an existing `http_connector` action. |
| `http_connector` (600) | none at the top level | **Fallback only** — reach for this over `web_connection` only for a genuine one-off call that will never be reused, or a documented gotcha a web connection hits (e.g. a reported multipart-form-on-GET issue — see `thinkwise-sf-web-connections`). Its configuration is not a separate child entity graph — it lives in the same `process_action_modeler_fixed_input`/`process_action_modeler_fixed_output` mechanism used elsewhere (see "Wiring runtime values through process variables" below), with `input_parmtr_id`/`output_parmtr_id` values like `http_con_url`, `http_con_http_method`, `http_con_content` pre-seeded and ready to edit. It has no reuse, no per-environment override, and no built-in response parsing — all reasons to default to `web_connection` instead. |
| `decision` (100) | none | See "Decision as a code-only step" below — this is also how you add a step that purely runs logic |

**Gotcha:** this is a `process_action`-specific instance of the general "a multi-field write can
silently drop one field, with no error" behavior documented in `thinkwise-sf-base`'s write
hazards — patching several fields on a fresh `process_action` in one call — especially the
composite key fields (`model_id`/`branch_id`/`process_flow_id`) alongside `process_action_id`, or
`process_action_id` alongside `process_action_type` — can leave a later field in that same call
silently reset to `null` in the response. **Separately, and not limited to batched calls**: patching
`process_action_type` or (for table-bound types) `tab_id` **or `task_id`** on its own can **overwrite
`process_action_id` with an auto-suggested id** derived from the type/table/task — e.g. setting
`tab_id` on an `activate_detail` action silently renamed it to `activate_detail_employee_absence`,
and setting `task_id` on an `execute_task` action equally renames it to `execute_task_<task_id>` —
discarding whatever id had been set moments before. The same happens on an **add**: setting type and
target makes the Software Factory rewrite the id to `<type>_<target>` (verified on SF 2026.2: `zz_exec`
became `execute_task_zz_probe_task`). **Order `process_action_id` last among the properties you set** — after `process_action_type` and
`tab_id`/`task_id` — and this is fixable in **one** combined `stage_resource`/`patch_resource` call, not
several: staging a fresh `execute_task` action with `process_action_type`, `task_id`,
`process_action_id`, `process_action_description` and further fields in one call, in that order,
commits with every field intact. Re-check the returned `fields` block on that one call
before moving on — read the id back, since later steps reference it — but there's no need to split the write into several
isolated single-field calls first; try the ordered combined call and verify its result before falling
back to isolation.

The same renaming makes **editing an existing action's type or target unreliable**: changing
`process_action_type`, `tab_id` or `task_id` on an existing action makes the Software Factory propose a
new id for it. To change what an action is or what it targets, delete the action and add it again.
Likewise, setting `web_connection_id` clears `web_connection_endpoint_id` — send the endpoint after the
connection.

`process_action_type` is an `Edm.Int32` enum keyed by numeric values (`start`=98, `execute_task`=60,
…) — patching it with the string label (`"start"`) can be rejected as an invalid value; pass the raw
integer instead (forcing a data-value interpretation on the connector if it supports one).

## Creating `process_step`

Mandatory: `model_id`, `branch_id`, `process_flow_id`, `process_step_id`, `last_process_action_id`,
`next_process_action_id`, `last_process_action_successful` (defaults to `always`=2),
`process_order_input` (default `true`), `process_order_output` (default `true`).

- **`process_step_id` is not generated** — it stays null and mandatory after `last_process_action_id`/
  `next_process_action_id` are set (verified on SF 2026.2). Send your own, conventionally
  `<from_action>_<to_action>`.

- `last_process_action_id` / `next_process_action_id` are plain string FKs to `process_action_id` —
  no lookup/resolve step, just pass the exact id string. **The referenced `process_action` rows must
  already exist.**
- `last_process_action_successful` enum: `not_successful` = 0, `successful` = 1, `always` = 2 — this
  is the green/red/blue branch condition from the designer canvas.
- On steps leaving `start` or a `decision`, `last_process_action_successful` is read-only (fixed at
  `always`) — omit it from the write instead of setting it.
- `order_no` is **not** mandatory (defaults to the highest existing `order_no` + 10); `abs_order_no` is read-only and auto-computed
  — don't try to set it.
- A single action can have several outgoing `process_step` rows; per §"Branching and loops" below,
  multiple outgoing steps run in parallel, and any step's `next_process_action_id` can point at an
  action *earlier* in the flow to form a loop.

**An error message emitted during a task does not necessarily mark the process action unsuccessful —
test the actual action status, not the presence of a message.** If routing depends on a real business
outcome, return/map an explicit status variable, or confirm the task's own abort semantics genuinely
produce the unsuccessful state the flow is routing on. See
`references/process_flow_design_guide.md`'s "Branching" section for the fuller reasoning on
Success/Not-successful/Always usage.

**Inserting an action into an existing chain is manual, not automatic.** Adding a new `process_action`
between two already-connected ones doesn't re-splice the existing `process_step` for you — explicitly
edit the existing step's `next_process_action_id` to point at the new action, then add a new step from
the new action to whatever the old step used to point at.

**Renaming a `process_action` does cascade automatically**, though: the rename operation updates every
`process_step.last_process_action_id`/`next_process_action_id` that referenced the old id, and the
step's own id, with no manual follow-up needed.

## Decision as a code-only step

A `decision` action runs a `PROCESSES` control procedure and nothing else — the way to add a step that
only evaluates logic. `use_processes` defaults to `true` and is read-only on this type.

- Run **Generate code group** for `PROCESSES` after adding the decision and its outgoing steps; it
  materializes the program object `prc_<process_flow_id>_<process_action_id>`. Assign the template to
  that object (see `thinkwise-sf-control-procedures`). The generation creates a `prc_` program object
  for **every** action in the flow, not only decisions — pick the decision's own object, and expect the
  others to sit empty.
- The generated procedure receives the flow's variables that have `process_input`/`process_output`
  set (so it can read and change them) plus one `int output` switch per outgoing step, named after
  that step's `process_step_id`: `@<process_step_id>` on SQL Server, `p_<process_step_id>` on
  PostgreSQL. Step ids conventionally read `<decision_action_id>_<next_action_id>`, so the switch
  usually looks like `@<decision_action_id>_<next_action_id>` — but read the real step ids rather than
  assuming that convention was followed.
- Set each of those to a positive number to follow that step (the number orders execution, depth
  first) and to `0`/`null`/negative to skip it. Set every one explicitly — e.g. `1` for the chosen
  branch and `0` for the rest — rather than relying on defaults. **With no template assigned to
  `prc_<process_flow_id>_<process_action_id>`, every outgoing step runs.**
- Outgoing steps from a decision stay `always`; the procedure, not the step condition, decides the route.
- A change to a variable (or its `process_input`/`process_output`) reaches the program objects only at
  the next `task_generate_code_grp` for `PROCESSES`.
- To read the assembled procedure without a full generation, stage `task_show_process_action_code` on
  the action, read its read-only `prog_object_item_code`, and abort the staged task instead of
  committing it.

## Creating `process_variable`

The add route depends on the domain layout:

- **(Indicium · single-domain)** add it through the entity-set variant
  `process_variable.process_variable_modeler` with parent `process_flow` (key `model_id, branch_id,
  process_flow_id`). A plain flat add on `process_variable` is refused with a parent-context error
  pointing only at `model_settings_modeler`.
- **(Indicium · split-domain)** a flat add on `process_variable` with the full key is accepted; the
  under-parent variant route works as well.

Create the variables **before** the actions whose parameters map to them.

Mandatory: `model_id`, `branch_id`, `process_flow_id`, `process_variable_id`, `dom_id` (a real domain
— required, no default), `type_of_default_value` (default `constant_value`=0; other value is
`expression`=1), `available_in_deep_link` (default `false`), `mand_in_deep_link` (default `false`),
`process_input` (default `true`), `process_output` (default `true`), `sub_flow_input` (default
`false`), `sub_flow_output` (default `false`).

Optional: `default_value` (used when `type_of_default_value=constant_value`), `default_value_query`
(hidden unless `type_of_default_value=expression`), `process_variable_description`.

For API-triggered system flows, `process_property` binds a variable directly to the HTTP context
instead of a normal default: `request_method`(0), `request_path`(1), `request_query_string`(2),
`request_headers`(3), `request_body`(4), `response_code`(5), `response_headers`(6),
`response_body`(7).
