# Quirks when scripting these changes through a metadata-driven modeling API

These apply broadly across entity types (domains, tables, columns, references, and beyond) whenever
the model is being edited through a metadata/staging-style write API rather than the Software Factory
UI directly, not assumed:

- **Enum-typed fields can reject the human-readable enum key even though it matches the field's own
  documented enum values, failing with an "invalid input"-style error.** Seen on a domain's default-value-type
  field, a table's table-type field, and a scheduler-style grouping-type field — three unrelated
  entities, same failure shape. If a plain enum key string is rejected, retry the same write using the
  raw underlying numeric value for that enum member instead of its name.
- **A combined write stops at the first property it refuses; the properties after it are not
  applied.** A field that is hidden or read-only for the record as it stands is refused
  (`field_not_editable`/`no_field_view`) and everything after it in the ordered list lands in
  `not_applied` — when the refused field happens to be last, it looks like "the last property silently
  dropped". Seen across task, table-task, task-look-up, control-procedure, menu, domain, and column
  writes, on every field shape (description text, order numbers, boolean flags, identifiers) — general
  write behavior, not a quirk of one field. The mechanism and the ordering rule live in
  `thinkwise-sf-base`'s "Hazards once real writes start". Practical pattern, held with zero drops across
  ~100 near-identical weak-entity creates (`elemnt`, `transl_object_transl`, `list_bar_item`): put
  every field in the initial `stage_resource` `properties` array, enabling fields before the fields
  they open, commit once, and re-read every written field.
- **Some fields only open once another field has a value.** Send the controlling field first (earlier
  in the same write, or in an earlier write):
  - `default_value` (constant) is editable only while `type_of_default_value` is 0 (constant); send it
    as text.
  - `grp_until` opens only once `default_sort` is true on that column.
  - `aggregation_summary_type` is hidden until `show_aggregation_in_grid` is true, then editable and
    mandatory; send it as a number (`"sum"` is refused) — see `references/grid_grouping.md`.
  - A primary key column gets `mand = true`, read-only.
  - `tab.allow_add = false` makes the Software Factory set `allow_copy = false` itself and lock it; an
    edit that sends only `allow_copy` has no editable field and fails with `no_field_view`.
  - `dom.rdbms_type` is not editable — never send it.
  - Fields the Software Factory sets itself: a numeric data type gets `alignment` 1 (right), and a
    `TIMESTAMP` data type gets control `DATETIME` (see also the `control_id`/alignment trap in
    `references/domains_and_elements.md`).
- **A table's child rows can carry their own separate NOT-NULL order-number field(s), distinct from
  and in addition to whatever `order_no` the row already has, with no database default.** Verified
  live on `col`: beyond its own `order_no`, a newly-inserted column also has `filter_order_no`,
  `search_order_no`, `grid_order_no`, `form_order_no`, and `card_list_order_no` — a hand-written
  `INSERT` that only populates `order_no` fails with a null-constraint error naming the friendly
  field (e.g. "Filter order number"), not the raw column name. The same shape hit `ref_col.order_no`
  ("Sequence no") — a reference's own child join-column rows need their position-derived `order_no`
  supplied explicitly too, it is not backfilled automatically. Before writing or reviewing any raw
  `INSERT`/`MERGE` against `col`, `ref_col`, or similar position-keyed child tables, check the target
  entity's full field list for additional NOT-NULL order-number fields beyond the one already in the
  insert list.
- **Requesting several large, property-heavy entity types' full metadata in one introspection call can
  overflow the response size limit.** Table-, column-, and reference-style entities in particular carry
  many properties, navigation properties, and bound actions — request at most one or two such entity
  types per introspection call rather than batching many together, especially early in a session
  before it's clear how large a given entity's schema is.
- **A weak entity's usual parent-based "add" can fail to resolve its parent even though the parent
  object genuinely exists** — seen when the parent lives outside the child's normal navigation context
  (e.g. a task's own parameter row, whose real parent is the task object itself rather than whatever
  table the task happens to be attached to). If a parent-based add returns a "parent not found"-style
  error for an object you've confirmed exists, fall back to a **plain add**, supplying the full
  compound key (including the columns that would normally come from the parent) as ordinary fields
  directly — this succeeds where the parent-nav path doesn't.
- **A description-style translatable field can appear as a normal editable field on a freshly-staged
  new record, yet a direct write to it is rejected outright** (an "unknown property"-style error, not a
  silent no-op) — unconfirmed root cause, but consistent with such fields routing through the
  translation-object mechanism rather than a plain column patch, at least before the record's first
  commit. If a description-style field's write is rejected this way, skip it during initial creation
  and set it afterward via `thinkwise-sf-translations` instead of retrying the
  same patch.
- **Never trust an unfiltered query to confirm an object exists in the model you're working in.** Many
  entity sets (e.g. `screen_type`) are not scoped to "the current model" by default — a query with no
  explicit `model_id`/`branch_id` filter can match rows belonging to a completely different model or
  branch in the same shared repository. A match under a bare `contains(...)`-only filter is not proof
  the object is usable in your model; always re-run the check with `model_id`/`branch_id` filters added
  before relying on the result — e.g. before assigning a system-provided screen type by name.
- **A new `screen_type` and its `screen_component` tree can be created through the write API**
  (verified on SF 2026.2; earlier sessions concluded otherwise). Components go under the screen type
  with an explicit `detail_nav` (the parent has two), and the Software Factory accepts a broken
  component tree without error — see `thinkwise-sf-subject-components`'
  `references/screen_types.md`. Still prefer reusing an existing screen type; see
  `thinkwise-sf-build-planner`'s interaction-surface step for asking the user what the screen should
  look like.
- **A blanket rejection on writes to an entity that should be editable can be a Software Factory
  role/rights gap on the current session's account, not a structural API limitation.** Confirmed live:
  an entity family that consistently rejected every add/edit attempt across several different approaches
  started working normally, with zero code or model changes, purely after the user adjusted the
  connected account's Software Factory roles/rights. Before concluding (and documenting) that some entity/task is
  unsupported through this kind of write API, consider asking the user to check their Software Factory
  role/rights configuration and retry — it can silently explain a failure that otherwise looks
  identical to a genuine connector/platform limitation.
  **The same gap can hide a task's existence entirely, not just block writes to an already-visible
  entity**: a bound task was completely absent from its entity's bound-task list, and
  a direct lookup by its exact name returned a hard "not found," indistinguishable from the task
  genuinely not existing on that entity — until the account's role/rights were adjusted, at which
  point the identical introspection call showed the task and flipped the entity's own
  add/update/delete permissions from all-denied to all-allowed. A task or entity that looks entirely
  absent from metadata, not just write-rejected, is still worth a role/rights check before concluding
  it isn't there.
