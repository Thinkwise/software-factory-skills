# Control procedure SQL authoring — dialects, style, dynamic model code, calculated columns

Loaded on demand from `thinkwise_sf_control_procedures`.

## The comment-block header — how generated code round-trips back to a template

Documented platform behavior, not independently verified live this session: the four-line comment
block already visible when reading `prog_object_generated_code` (see point 2 of "Actually generating
code" above) is also the contract the Factory uses to identify a woven item when code is hand-edited
directly (only possible on an object that's just header/footer, per the 2026.1+ editing limits noted
earlier):

```sql
--control_proc_id:      default_fill_address
--template_id:          fill_address
--prog_object_item_id:  fill_address
--template_description: Fill in the default address
```

Rules worth knowing before touching this text by hand: keep all four lines, in this order — omitting
the first means the item isn't detected at all; omitting any other errors on save. **Never rename by
editing the header** — changing `control_proc_id`/`template_id` there doesn't rename, it creates a
*new* control procedure/template; rename through the proper task instead (see below). A
`control_proc_id` that doesn't exist yet gets created automatically from the header, which is
convenient but means a typo silently spawns a stray procedure — confirm the id first. Duplicate
`prog_object_item_id`s error on save.

## Naming guidelines

- **Control procedure IDs**: name the *purpose* the templates accomplish, not the plumbing — skip
  the code group, table name, and generic words like "default"/"task". Good:
  `calculate_discount_amount`, `revoke_user_access`, `send_order_confirmation`,
  `archive_old_tasks`. Avoid: `default_sales_order`, anything restating "this is a default/task".
- **Template names**: one template = one piece of functionality, no hidden dependency on a sibling
  template. Match the procedure's name if there's a single template; give distinct names to
  siblings otherwise. Avoid placeholders like `template1`.

## Writing dynamic model code (meta control procedures)

For writing dynamic/meta control procedures (model-generation-time SQL, tag-driven codegen,
`rdbms_type` fan-out via `branch_rdbms_type`), read `references/dynamic_model_code.md`.

## Writing SQL in the right dialect

**Before writing any SQL in a control procedure template, read `references/sql_dialects.md`** to
confirm the right dialect/helper functions for the target RDBMS. Query `branch_rdbms_type` first (see
the top of this doc) — don't assume, don't default to T-SQL out of habit. That reference file covers
all four target platforms (SQL Server, DB2 iSeries, Oracle, PostgreSQL): Thinkwise's dialect-safe
helper functions (`tsf_user`, `tsf_send_message`, identity retrieval in a Handler) and the
null-fallback/current-timestamp/string-concat/row-limit comparison table for whatever has no
Thinkwise helper. This is also the canonical copy of this material for other Thinkwise skills
(create_view, maps_component) that need SQL-dialect guidance.

## Thinkwise SQL coding guidelines

**Before writing or reviewing any control-procedure SQL body, read `references/sql_style_guide.md`.**
It covers the most important rule first — match the codebase's existing style over any
"technically more correct" alternative — plus the general style rules (avoid `distinct`/`union`
without `all`, cursor discipline, `begin`/`end` everywhere, `tsf_send_message` not `raiserror`,
transaction pairing), the per-code-type restrictions (Triggers/Defaults/Layouts/Contexts/Processes/
Tasks/Subroutines), formatting conventions, and a full anti-pattern-vs-efficient-rewrite SQL example
(cursor-based trigger vs. the equivalent set-based `insert...select`). This is also the canonical copy
of this material for other Thinkwise skills that need SQL style guidance.

## Calculated columns — the 2026.2 `_query`-split pattern

For why calculated columns and the broader 2026.2 `<entity>_query`-split family (`dom_query`,
`tab_prefilter_query`, `col_query`, etc.) aren't safe to target with hand-written DML, and how to
detect a moved field before writing against it, read `references/calculated_columns_query_split.md`.
