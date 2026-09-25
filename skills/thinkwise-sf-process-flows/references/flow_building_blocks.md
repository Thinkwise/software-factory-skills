# Creating process flows, actions, steps, and variables

Loaded on demand from `thinkwise_sf_process_flows`.

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
| `web_connection` (602) | `web_connection_id` (mandatory), `web_connection_endpoint_id` (mandatory) | **The preferred choice for any HTTP/REST call — build the connection and its endpoint(s) first**, via `thinkwise_sf_web_connections` (domain `sf/manage_webconnections`, a *different* domain from this one). An earlier version of this note, based on inspecting `web_connection`/`web_connection_endpoint` only through `sf/manage_process_flows` (where a process action merely references a connection/endpoint by id), wrongly concluded the objects exposed "almost no writable configuration" — read through the correct domain, they carry full configuration (base URL, auth, method, path, body, headers, output parsing) and are fully buildable through the API. Once the connection exists, this action's own inputs/outputs are the pre-seeded `process_action_web_connection_endpoint_parmtr_input_parmtr` / `process_action_web_connection_parmtr_input_parmtr` (in) and `process_action_modeler_web_connection_endpoint_output` (out) rows — see that skill for the full field/enum reference and worked examples. The domain also exposes a bound migration task on this action, `task_enrichment_conv_http_connector_to_web_connection`, for converting an existing `http_connector` action. |
| `http_connector` (600) | none at the top level | **Fallback only** — reach for this over `web_connection` only for a genuine one-off call that will never be reused, or a documented gotcha a web connection hits (e.g. a reported multipart-form-on-GET issue — see `thinkwise_sf_web_connections`). Its configuration is not a separate child entity graph — it lives in the same `process_action_modeler_fixed_input`/`process_action_modeler_fixed_output` mechanism used elsewhere (see "Wiring runtime values through process variables" below), with `input_parmtr_id`/`output_parmtr_id` values like `http_con_url`, `http_con_http_method`, `http_con_content` pre-seeded and ready to edit. It has no reuse, no per-environment override, and no built-in response parsing — all reasons to default to `web_connection` instead. |
| `decision` (100) | none | See "Decision as a code-only step" below — this is also how you add a step that purely runs logic |

**Gotcha:** this is a `process_action`-specific instance of the general "a multi-field write can
silently drop one field, with no error" behavior documented in `thinkwise_sf_data_model`'s
quirks section — patching several fields on a fresh `process_action` in one call — especially the
composite key fields (`model_id`/`branch_id`/`process_flow_id`) alongside `process_action_id`, or
`process_action_id` alongside `process_action_type` — can leave a later field in that same call
silently reset to `null` in the response. **Separately, and not limited to batched calls**: patching
`process_action_type` or (for table-bound types) `tab_id` **or `task_id`** on its own can **overwrite
`process_action_id` with an auto-suggested id** derived from the type/table/task — e.g. setting
`tab_id` on an `activate_detail` action silently renamed it to `activate_detail_employee_absence`,
and setting `task_id` on an `execute_task` action equally renames it to `execute_task_<task_id>` —
discarding whatever id had been set moments before. **Order `process_action_id` last among the properties you set** — after `process_action_type` and
`tab_id`/`task_id` — and this is fixable in **one** combined `stage_resource`/`patch_resource` call, not
several: verified live (`RK_SCHEDULER_TEST`), staging a fresh `execute_task` action with
`process_action_type`, `task_id`, `process_action_id`, `process_action_description`, and four more fields
all in one call, in that order, committed with every field intact — `process_action_id` was not
overwritten and the description did not revert. Re-check the returned `fields` block on that one call
before moving on, rather than assuming it landed — but there's no need to split the write into several
isolated single-field calls first; try the ordered combined call and verify its result before falling
back to isolation.

`process_action_type` is an `Edm.Int32` enum keyed by numeric values (`start`=98, `execute_task`=60,
…) — patching it with the string label (`"start"`) can be rejected as an invalid value; pass the raw
integer instead (forcing a data-value interpretation on the connector if it supports one).

## Creating `process_step`

Mandatory: `model_id`, `branch_id`, `process_flow_id`, `process_step_id`, `last_process_action_id`,
`next_process_action_id`, `last_process_action_successful` (defaults to `always`=2),
`process_order_input` (default `true`), `process_order_output` (default `true`).

- `last_process_action_id` / `next_process_action_id` are plain string FKs to `process_action_id` —
  no lookup/resolve step, just pass the exact id string. **The referenced `process_action` rows must
  already exist.**
- `last_process_action_successful` enum: `not_successful` = 0, `successful` = 1, `always` = 2 — this
  is the green/red/blue branch condition from the designer canvas.
- `order_no` is **not** mandatory (defaults to `50`); `abs_order_no` is read-only and auto-computed
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
step's own generated id, with no manual follow-up needed.

## Creating `process_variable`

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
