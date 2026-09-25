# PostgreSQL-specific errors — name collisions, MERGE/FK, and seed data

Loaded on demand from `thinkwise_sf_postgresql_migration`.

## Domain/column name collisions — PostgreSQL-specific validation

**Symptom**: model validation reports something like "PostgreSQL cannot have the same name for
different objects within the same schema," or more specifically, a domain and a column sharing a name.

**Cause**: Thinkwise's own naming convention commonly names a domain identically to the column it
canonically backs (`email_address` domain for an `email_address` column, `active` for `active`, `name`
for `name`, and so on) — completely normal and harmless on platforms where the generated schema keeps
different object kinds apart. On this model's generated PostgreSQL output, tables, views, procedures,
and functions all land in one flat `public` schema, and this validation catches every domain whose bare
name would collide with a column using it. **This is usually widespread, not an isolated pair**, 22 of ~50 domains in one mid-sized model collided this way. Check every domain against
every column before assuming it's a one-off:

```
GET /col?$filter=model_id eq '<model>' and branch_id eq '<branch>'&$select=tab_id,col_id,dom_id
```

Cross-reference `dom_id` against `col_id` for an exact string match (case-sensitive). Domains with no
column of the exact same name — `id`, `money_amount`, `calendar_date`, etc. in the reference model —
are unaffected; don't rename those.

**Fix**: rename the *domain*, never the column. `dom_id` is a pure modeling identifier — renaming it
via `task_rename_dom` (`from_dom_id`/`to_dom_id`; `from_dom_id` is derived from the key and read-only,
patch only `to_dom_id` after staging) changes nothing about the physical column name generated on any
platform, so it's a safe, fully backward-compatible fix that doesn't touch the already-working
SQL Server deployment. **Ask the user for a naming convention before renaming anything** (`dom_`
prefix, `_dom` suffix, or a case-by-case pass) — this is a real design choice affecting how the domain
list reads afterward, not a mechanical detail to default silently (see `thinkwise_sf_base`'s "Ask, don't default"). Apply the same convention across every colliding domain in one pass
once chosen.

**Open, unresolved as of this writing**: a related validation message — "Another object has the same
name as the input constraint" — was hit in the same migration and *not* resolved. `dom_input_constraint`
came back completely empty for the model, ruling out the obvious cause (a domain-level constraint
reused identically across every column sharing that domain). The actual mechanism behind this specific
message is still unknown — get the *exact, full* validation text (Thinkwise validators normally name
the specific offending object) before guessing further, and check whether it recurs after the
domain-rename fix above, since some "input constraint" naming may itself derive from the domain name.
Update this section once resolved.

## MERGE/FK errors during generation — a repository-internal issue, not application data

**Symptom**: generating a framework `UPGRADE`-group object (e.g. `upgrade_pg_insert_data_in_new_tables`)
throws something like *"The MERGE statement conflicted with the FOREIGN KEY constraint
'ref_prog_object_item_prog_object_item_parmtr'"*, naming a database like `..._SF`.

**This is the Software Factory's own repository database, not the target application.**
`prog_object_item`/`prog_object_item_parmtr` are Thinkwise meta-model bookkeeping tables (the same ones
this skill's own writes go through), not anything in the deployed app. The specific control procedure
uses the **Staged** generation strategy — populate a temp table with the desired end-state, `MERGE`
against the real tables — and this trips when the model has a very large number of PostgreSQL objects
being generated for the first time simultaneously (verified live: ~1000 objects still
`generated_code_stale = true` after just enabling the platform, since *every* object across the whole
model gets a stale placeholder, not just the ones with custom logic).

**Fix attempted, not fully verified**: generate plain table objects first (filter to `table_*`/
`ug_table_*`), commit, *then* retry the failing `UPGRADE` step — if this is a first-time-batch ordering
issue, materializing the base tables first should let the dependent step succeed. If it still fails,
this is a Software Factory product-level edge case worth reporting to Thinkwise support rather than
something fixable through model changes — a `MERGE`-based FK conflict inside the generation engine
itself isn't reachable through the modeling API.

## Seed/demo data — mechanical but bulk

`UPGRADE`-group scripts seeding demo/reference data are typically large (multi-thousand character)
`if not exists / insert` blocks, idempotent by natural key. The dialect substitutions needed are
mechanical (see the reference table) — `getdate` → `current_date`/`current_timestamp`, hex color
literals (`convert(int, 0x2196f3)`) → `x'2196f3'::int`, `1`/`0` literals on boolean-backed columns →
`true`/`false`. **Known tooling limitation**: `execute_odata_query` was observed to hard-truncate a
long `template_code`/similar text field at ~5000 characters with no working chunked-read path found in
this domain (`$apply=compute(substring(...))` was attempted and silently ignored). For a script larger
than that, don't attempt a piecemeal reconstruction that risks silently dropping content — tell the
user directly and recommend finishing that specific script via copy/find-replace in the Software
Factory's own UI instead of guessing at unseen content.
