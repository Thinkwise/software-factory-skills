# Table-level and per-column enablement flags

Loaded on demand from `thinkwise_sf_control_procedures`.

### Table-level enablement flags — verify, don't assume

Whether a code type's business logic runs *at all* for a given table is a per-table boolean on the
`tab` entity (`data_modeling` domain): `use_defaults` (Default), `use_layouts` (Layout),
`use_contexts` (Context), `use_badges` (Badge), `use_change_detection` (Change detection),
`use_insert_handlers`/`use_update_handlers`/`use_delete_handlers` (Handlers). These are the model's
real names for the "Use default/layout/context/… concept" checkboxes shown in the Software Factory
UI at the table level. An existing `prog_object` row (e.g. `default_absence`) does NOT imply this
flag is on — a table can have a Default `prog_object` (framework `defaults_start`/`defaults_end`
wrapper only, no real logic) while `use_defaults` is still `false`. Check with `execute_odata_query`
against `tab` (`$select=use_defaults,use_layouts,use_contexts,use_badges,use_change_detection,
use_insert_handlers,use_update_handlers,use_delete_handlers`) *before* declaring an assignment
complete, and enable any that are off via `stage_resource`(edit)/`patch_resource`/`commit_resource` on
the `tab` row, then re-run `generate_code_grp`.

### Per-column enablement flags — verify, don't assume

Whether a specific *column* actually participates in a code type's business-logic variables is a
separate, per-column setting, exposed as boolean flags on the `col` entity (`data_modeling` domain):
`default_input`/`default_output` (Default), `layout_input`/`layout_type_output`/`layout_mand_output`
(Layout), `context_input` (Context), `function_input` (function/task parameters). These are the
model's real names for what's shown in the Software Factory UI as "Default"/"Layout"/"Context"
checkboxes on a column. **Do not assume a newly-added or existing column has these on** — check them
with `execute_odata_query` against `col` (`$select=default_input,default_output,layout_input,...`)
*before* writing a template that references `@[col_id]`/`p_[col_id]` for that column, and again after
if the flags were off, since a control procedure referencing a column whose corresponding
input/output flag is disabled either won't have that variable generated at all or won't have the
assignment persisted back to the column. If a flag is off and the logic genuinely needs it, enable it
via `stage_resource`(edit)/`patch_resource`/`commit_resource` on the `col` row first, then write/assign
the template.

**Column flags being on is not sufficient by itself** — see the table-level flags above. A column can
have `default_input`/`default_output = true` while the table's `use_defaults = false`, in which case
the assigned logic still won't run. Check both.
