# Known API/tooling quirks specific to a PostgreSQL migration

Each entry: symptom, root cause, and what actually worked (or the honest state if unresolved).
Complements the general write-hazard list in `thinkwise-sf-base` — these are
specific to enabling and porting to PostgreSQL, not general MCP-connector behavior.

## `branch_rdbms_type` is not directly writable — enabling a platform goes through a task

**Symptom**: `branch_rdbms_type` reports `allow_add/update/delete = false`, so a direct add of a
PostgreSQL row is refused.

**Resolution**: the entity carries bound tasks — `task_link_branch_rdbms_type` /
`task_unlink_branch_rdbms_type` (`model_id`, `branch_id`, `rdbms_type`) and `task_mass_conv_code`
(AI conversion of the branch's code from `source_rdbms_type` to `target_rdbms_type`, with a
`template_prefix` and one `conv_*` flag per logic concept). Stage the link task on an
existing `branch_rdbms_type` row of the branch (e.g. `rdbms_type` 0) and pass the new platform as the
`rdbms_type` parameter — staging it on the PostgreSQL key that doesn't exist yet gives 404. Committing
it is unverified: try it once; if it is refused, enabling a platform is a Project settings action in the
Software Factory's own UI — tell the user and wait for confirmation before proceeding.

## Prefilter/domain/column query fields gained an `rdbms_type` dimension in 2026.2 — older guidance is stale

Some existing skill text (written before this split) states `tab_prefilter.query` has "no `rdbms_type`
dimension" and must be written portably in one slot. **This is no longer true as of 2026.2** — verified
live: `tab_prefilter_query` (a distinct child entity from `tab_prefilter`) is keyed by
`(model_id, branch_id, tab_id, tab_prefilter_id, rdbms_type)` and holds the actual `query` text per
platform, same shape as `dom_query` and `col_query`. Don't trust a skill's specific claim about which
fields are/aren't platform-split without checking `get_entity_definition` live first — this family
(`col_query`, `dom_query`, `tab_prefilter_query`, `tab_check_constraint_query`, `indx_query`,
`process_variable_query`, `report_parmtr_query`, `task_parmtr_query`, `subroutine_parmtr_query`,
`data_set_query`, `tab_query`, `unit_test_query`, `tab_data_col_query`, `dom_input_constraint_query`)
is actively growing across platform versions — see
`thinkwise-sf-control-procedures`'s `references/calculated_columns_query_split.md`
for the general detection technique.

## `execute_odata_query` truncates long text fields with no working chunked-read path

**Symptom**: reading a large `template_code`/similar field returns
`"[TRUNCATED: showing 5000 of 14393 characters]"` embedded in the response text itself (not a
tool-level "output too large" error with a file fallback — the truncation is inside the JSON payload).

**Attempted and failed**: re-querying the identical field a second time returns the identical
truncated 5000 characters (not a different window). Adding `$apply=compute(substring(template_code,
4500, 4500) as chunk2)` to the query was silently ignored — the response still returned the plain
(truncated) `template_code` field, no `chunk2` field appeared at all, meaning the connector doesn't
implement OData `$apply`/`compute` for this entity.

**No workaround found in this domain.** For a field long enough to hit this limit (a large seed-data
script is the most likely case), don't attempt a partial reconstruction — tell the user the specific
object is too large to read completely through the connector and hand that one off to be finished
directly in the Software Factory's UI (copy/paste + find-replace for the known mechanical
substitutions is enough for seed data specifically, since the content is repetitive `insert` blocks,
not novel logic).

## A brand-new (never-generated) standalone subroutine has no placeholder yet

**Symptom**: `template_prog_object_item`/`prog_object_item` queries for the subroutine return nothing
on *any* platform although the `control_proc`/`control_proc_template` rows exist and look complete.

**Resolution**: run `task_generate_code_grp` bound to the subroutine's own control procedure. It
creates the `func_`/`proc_` placeholder when the `subroutine` and `subroutine_parmtr` rows were created
before the control procedure (see `thinkwise-sf-subroutines` → `references/creating_a_subroutine.md`).
If the generate completes but still creates nothing, check that order first. Only then fall back:
write and save the PostgreSQL `control_proc_template` anyway (`allow_add`/`allow_update` are `true` on
it) and tell the user this subroutine needs one manual "Generate" pass in the Software Factory. Anything
that `call`s it (a Handler, a Task) generates fine but fails at database deploy until that happens —
flag the dependency, don't let it look like the migration silently succeeded.

## `task_generate_code_grp` has broader side effects than documented

**Symptom**: calling `task_generate_code_grp` bound to one control procedure (say, a trigger) to
materialize its own missing placeholder also produces stale placeholders for many unrelated objects on
the same table — badges, change-detection, generic CRUD triggers, `UPGRADE`-group objects — that
weren't the target of the call at all.

**Practical implication**: after any single `task_generate_code_grp` call, don't assume only the
object you were targeting changed state. If auditing what's stale/generated across the model, re-query
broadly (`generated_code_stale eq true` across the whole `rdbms_type`) rather than trusting that only
touched objects moved. This bulk materialization is also the direct cause of the very large stale-object
count that can trigger the MERGE/FK issue below — enabling a platform on a model with substantial
existing content routinely leaves many hundreds of objects stale simultaneously, and any subsequent
generation pass across the whole model has to process that whole batch at once.

## `MERGE` FK conflict generating a framework `UPGRADE` object at scale

See the SKILL.md section "MERGE/FK errors during generation" for the full writeup — summarized here as
a quirk-list entry: this is a Software Factory repository-internal issue (the error names a database
like `..._SF`, which holds `prog_object_item`/`prog_object_item_parmtr` meta-tables, not the deployed
application), surfaced by generating an `UPGRADE`-group object (`upgrade_pg_insert_data_in_new_tables`
specifically, but potentially any object in that group) while a very large number of PostgreSQL objects
are stale/ungenerated for the first time across the whole model. Generating base tables first, then
retrying, is the first thing to try; if it recurs, it's a product-level report to Thinkwise, not
something fixable from the modeling API.

## "Another object has the same name as the input constraint" — unresolved

See SKILL.md's "Domain/column name collisions" section for what was ruled out (`dom_input_constraint`
is empty in the affected model, so it isn't a domain-level constraint reused identically across
columns sharing a domain). The actual mechanism is still unknown as of this writing. If you hit this
message: get the full, exact validation text first (it likely names the specific object), check
whether renaming colliding domains (the fix for the sibling "same name for different objects" error)
also resolves this one as a side effect, and update this file with whatever's found — don't re-guess
from scratch.
