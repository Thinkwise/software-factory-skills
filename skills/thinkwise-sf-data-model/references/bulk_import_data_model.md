# Bulk-importing a whole data model in one call — check for a custom task first

Some repositories have a **custom-built** task (not a standard Software Factory feature — added
per-repository or per-model, so it may or may not be present where you're working; when present it
tends to be available across every model in that repository, including brand-new ones) that accepts
a single JSON payload describing a batch of domains/tables/columns/indexes/references and upserts
all of it in one call, instead of creating each object individually via the flow described in the
rest of this skill. If present, it's typically named something like `bulk_import_data_model_json`
and is an **unbound** task (parameters `model_id` / `branch_id` / `json_payload`).

**Check availability before assuming it exists** — via the connector's task-discovery flow
(`search_capabilities`/`search_domain_capabilities`/`get_task_definition`, or equivalent) — don't
assume it's there just because a previous session built one, in this model or a different one; it
is not a platform feature. **If found, confirm its exact task/parameter names and JSON shape via
`get_task_definition`/its own documentation before calling it** — it's hand-written and can differ
from or extend what's shown here.

**This kind of task may live in its own dedicated domain, separate from the data-modeling domain
routine capability searches default to.** Verified live: a capability search scoped to the
data-modeling domain found nothing, while a full domain listing filtered by keyword turned up the
task immediately in a completely separate, otherwise-unrelated-sounding domain. If a targeted search
for a known task name comes up empty, fall back to listing all domains and grepping their
descriptions before concluding the task doesn't exist.

As built in one reference model: parameters `model_id`, `branch_id` (target scope) and
`json_payload` (a large text parameter), with this shape:
```json
{
  "domains": [ { "dom_id": "...", "dttp_id": "...", "length": 0, "prec": 0, "mand": true, "dom_description": "..." } ],
  "tables": [
    {
      "tab_id": "...",
      "type_of_table": 0,
      "tab_description": "...",
      "columns": [ { "col_id": "...", "dom_id": "...", "primary_key": true, "mand": true, "identity_col": false, "col_description": "..." } ],
      "indexes": [ { "indx_id": "...", "unique_indx": true, "columns": ["col_id", "..."] } ]
    }
  ],
  "references": [
    { "ref_id": "...", "source_tab_id": "...", "target_tab_id": "...", "columns": [ { "source_col_id": "...", "target_col_id": "..." } ] }
  ]
}
```
Upsert-only (matches by natural key, never deletes existing objects). Primary keys are expressed
purely via each column's `primary_key` flag, not a modeled index (see "When to use a unique index"
below) — `indexes` is only for genuinely additional secondary/unique indexes. Processing order:
domains → tables → columns → indexes → references.

**NUMERIC domains**: in `domains[]`, for `dttp_id: "NUMERIC"`, `length` is the precision (total
digits) and `prec` is the scale (decimal places) — `{"dttp_id":"NUMERIC","length":9,"prec":2}`
produces `NUMERIC(9,2)`. Verified against live `dom` samples; the field names don't make this
obvious.

## What it sets automatically — it is not a bare skeleton

**When this task exists in the repo, it is the strongly preferred first path**, not a rough
scaffold you then have to flesh out object by object. Verified live across a two-payload build of a
from-scratch model (15 tables / 111 columns / 23 references / 6 unique indexes), it sets far more
than the raw rows:

- **Column `order_no`** — assigned from each table's `columns[]` array order in increments of 10
  (10, 20, 30 …). No separate ordering pass needed; put the columns in the payload in the order you
  want them.
- **`primary_key` / `identity_col` / `mand`** — applied exactly as given. The *"a column added
  before the table's real primary key can silently default `primary_key = true`"* quirk under the
  main skill's "Column order" section did **not** occur here — bulk import commits a table's whole
  column set in one operation, so that ordering hazard doesn't apply. A quick spot-check afterward
  is still cheap, but it is not the near-certainty the per-object flow warns about.
- **`foreign_key` flag** — auto-set on any column named as a `target_col_id` in `references[]`.
- **`ref` + `ref_col`** — created with `check_ref = true` and `on_delete` / `on_update =
  no_action` (0) by default. For a **self-referencing** reference (`source_tab_id == target_tab_id`)
  that default is exactly what SQL Server requires — no manual downgrade from a cascade action is
  needed (contrast the per-object flow, where you'd set `no_action` by hand).
- **Unique indexes** — created from each table's `indexes[]` entries (`unique_indx: true`), with
  the `indx_col` child rows positioned automatically.
- **`transl_object_transl` rows for every new `tab` and `col`** — generated from the names /
  descriptions in the payload. The branch-wide `startswith(transl,'[')` placeholder scan comes back
  **near-empty** straight after a bulk import; only objects added *afterward by other paths*
  (calculated columns, domain elements, menu groups/items) still carry bracket placeholders to
  fill.

### What it still does NOT set — genuine follow-up pass

`elemnt` (domain element rows) and `dom.control_id`; calculated columns (`calculated_field_type` /
`calculated_field_query`); form / grid column groups; `tab.look_up_display_col_id`;
`tab.icon_id` and column navigation icons; per-column sort / search / filter fields;
`type_of_col` / `grid_type_of_col` / `form_type_of_col` visibility; data-sensitivity
classification. Handle these per the rest of this skill after the import.

### `ref_add` in the payload is ignored

`ref_add` is not a field on `ref`, and passing it in a `references[]` entry has no effect. To avoid
an auto-derived `ref_id` collision when one child table has two FK columns pointing at the same
parent (e.g. `employee_absence.employee_id` **and** `.approved_by_id` → `employee`), just give each
`references[]` entry its own **distinct explicit `ref_id`** — that alone keeps them from
overwriting each other.

**If no such task is found, or calling it fails, fall back to the normal flow**: create each
domain/table/column/index/reference individually following the rest of this skill, in the same
dependency order — nothing else in this skill assumes the bulk task exists.
