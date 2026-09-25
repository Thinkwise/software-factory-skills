# Wiring runtime values through process variables

Loaded on demand from `thinkwise_sf_process_flows`.

## Wiring runtime values through process variables

An action's actual inputs/outputs are junction entities named
`process_action_modeler_<kind>_<input|output>`: `process_action_modeler_fixed_input`/
`process_action_modeler_fixed_output` (literal/enum config values and their captured results, e.g. a
connector's URL in, its response body out, or `open_document`'s floating/modal switch),
`process_action_modeler_col_input`/`_col_output` (a table column, e.g. a `change_filter` condition or
a captured row value), `process_action_modeler_task_parmtr_input`/`_task_parmtr_output` (a task's own
parameters), plus `sub_flow`/`report_parmtr`/`message_broker_message` variants for those action
types — pick the one matching what the action actually is, not one generic table for all of them.
**For a `web_connection` action specifically**, the equivalents are
`process_action_web_connection_endpoint_parmtr_input_parmtr` (endpoint input),
`process_action_web_connection_parmtr_input_parmtr` (connection-level input), and
`process_action_modeler_web_connection_endpoint_output` (output) — see
`thinkwise_sf_web_connections` for the full field reference.

**A generically-named `process_action_output_parmtr` entity also exists and looks like "the" output
entity from its own definition (it even carries the same `output_parmtr_id` enum as
`process_action_modeler_fixed_output`) — but `add` against it is rejected outright (403) through this
API.** It appears to be a newer, unified/read-oriented scheme that isn't (yet) a valid
write path here. For capturing a connector-type action's output (`http_connector`, `ftp_connector`,
`db_connector`, etc.) into a variable, use `process_action_modeler_fixed_output` instead — same
pre-seeded/edit-only pattern as `process_action_modeler_fixed_input` below, keyed by `output_parmtr_id`
(e.g. `http_con_content` for an HTTP response body), with a `process_variable_id` field to set.

**These rows are pre-seeded, not freely addable.** The moment a `process_action`'s type (and, for
column-based ones, its `tab_id`) is set, one placeholder row per relevant column/parameter already
exists — e.g. one `_col_input` row per column of the action's table, one `_fixed_input` row per input
parameter that type supports. **Staging an `add` on any of these child entities is rejected outright**
(before you even get to set a field) — query for the existing placeholder row first (filter by
`process_action_id`), then stage an `edit` against its full composite key (including
`tab_id`/`col_id`/`input_parmtr_id`/`task_parmtr_id` as applicable) instead.

**Worked pattern — filtering a popup to the row that triggered the flow** (the shape behind
"double-click a row → modal popup of related, filtered records"):

1. The trigger is normally an `execute_tab_task` action running a table task bound via
   `grid_double_click`. **The row's data does not reach the flow through
   `process_action_modeler_col_output` on this action** — that entity stages and commits without error
   but silently captures nothing usable for an `execute_tab_task`. Instead, add a `task_parmtr` on the
   underlying table task itself (e.g. `employee_id`) with **both** `task_input=true` (so a
   `tab_task_parmtr` binding can auto-fill it from the selected row's column) **and**
   `task_output=true` (so its value becomes readable by the flow).
2. Create a `process_variable` with a matching `dom_id`.
3. On the triggering `execute_tab_task` action, edit its pre-seeded
   `process_action_modeler_task_parmtr_output` row for that `task_parmtr_id`, setting
   `process_variable_id` to the variable — this is what actually carries the selected row's value into
   the flow.
4. Open the popup with an `open_document` action, then follow it with a `change_filter` action on the
   same table. Edit that action's pre-seeded `process_action_modeler_col_input` row for the FK column,
   set `assignment_method='variable'` (`process_variable_id` often auto-resolves on an unambiguous
   name/domain match, but verify it).
5. For the popup's modal behavior itself: `open_document` actions get a pre-seeded
   `process_action_modeler_fixed_input` row keyed by `input_parmtr_id='open_doc_floating'` — edit it to
   `assignment_method='literal_constant'`, `constant_enum_value='open_doc_floating_modal'`.

**A given `process_variable` can only be the output target of one binding per action.** Assigning two
different output rows on the same action to the same variable (e.g. both a `col_output` and a
`task_parmtr_output` pointed at the same variable, left over from an earlier wrong attempt) causes a
real duplicate-key failure on the second commit — clear/null the first binding before setting the
second.
