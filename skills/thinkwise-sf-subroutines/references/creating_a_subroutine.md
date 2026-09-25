# Step-by-step: creating a subroutine, options, and role rights

Loaded on demand from `thinkwise_sf_subroutines`.

## Step-by-step: creating a subroutine

1. **Query `branch_rdbms_type`** (see `thinkwise_sf_control_procedures`) before
   anything else — it determines both the buildable `subroutine_type` set and the SQL dialect the body
   will be written in.
2. **Create the `subroutine` row**: `subroutine_id` (name for purpose, see "Naming" below),
   `subroutine_type_id` (from the live `subroutine_type` list), `return_value`, and
   `return_scalar_dom_id`/`return_table_id` to match. Leave `api`/`basic_api` off until the contract is
   stable (see "Publishing as an API" below). Decide `single_transaction` now (see "Transaction
   behavior").
3. **Add `subroutine_parmtr` rows**, one per input/output, each with a real business-specific `dom_id`,
   explicit `order_no`, and `input_parmtr`/`output_parmtr` set — don't rely on either flag's default.
4. **If `return_value = table`**, add `subroutine_return_col` rows the same way, plus `primary_key`/
   `mand` where applicable.
5. **Add `subroutine_option` rows** for anything beyond the platform default (see table above).
6. **Grant role execute rights** — see "Role rights" below. Don't skip this; a subroutine with no
   granted role can still generate and deploy cleanly while being uncallable at runtime for every role
   that needs it.
7. **Write and assign the body** — this is where subroutine work rejoins the general control-procedure
   flow. Concretely:
   - **Code group**: `FUNCTIONS` for a Function returning `none`/`scalar`, `TABLE_VALUED_FUNCTIONS` for
     a Function returning `table`, `PROCEDURES` for a Procedure (any return value). Confirm against
     `code_grp` for the model rather than assuming these three are the only options — CLR/DLL types have
     their own code groups (`CLR_FUNCTIONS`, `CLR_PROCEDURES`, `CLR_ASSEMBLIES`).
   - **`prog_object_id` naming, verified**: `func_<subroutine_id>` for a Function, `proc_<subroutine_id>`
     for a Procedure — this prefix is purely internal bookkeeping.
   - **The real generated database object name is the bare `subroutine_id`**, no prefix — confirmed by
     reading a generated function's text (`create or alter function "tsf_user" (...) ...`). Don't
     expect `func_`/`proc_` to appear in the deployed SQL.
   - **`control_proc_type = 1` (`program_object_item`), `assign_type = 0` (Static)** is the normal shape
     for a subroutine's own hand-written body — one control procedure, one template, one
     `template_prog_object_item` row pointing at `func_<id>`/`proc_<id>`, exactly as documented in
     `thinkwise_sf_control_procedures`'s "Creating and assigning a control
     procedure — step by step" section. Follow that section verbatim from here, including its dialect
     checklist and the "leave the template blank, generate first to see the real scaffold" step.
   - **Business-logic variables inside the body are just the subroutine's own declared parameters** —
     `@[subroutine_parmtr_id]` in T-SQL (`p_[subroutine_parmtr_id]` in PostgreSQL), not one of the
     Default/Layout/Handler-style variable sets in that skill's `references/code_type_variables.md`.
     There's no separate "input/output variable" table for subroutines because the parameter list *is*
     the variable list.
8. **Generate and verify** — same two-task flow as any other code type
   (`task_generate_code_grp` → `task_add_job_to_generate_object_code`, confirmed via
   `generate_object_code_status`/`generated_code_stale`, then read the generated text). **Known gap for
   a genuinely brand-new standalone subroutine** (verified live in the sibling skill): a subroutine with
   no existing table/view/task to hang off of may never get its placeholder `prog_object` materialized
   through `task_generate_code_grp` — two different attempts both left no row behind, without erroring.
   The `subroutine`/`subroutine_parmtr`/`subroutine_return_col`/`control_proc`/template rows can still
   be fully authored and reviewed through the API regardless. Try the normal generate flow first (it may
   simply work); if no `prog_object` row appears afterward, treat the final generate as a manual step in
   the Software Factory's own UI and say so, rather than continuing to retry alternate API paths.
9. **Copy / rename / delete** — all bound tasks on `subroutine`, verified: `task_copy_subroutine`
   (`from_subroutine_id`, `to_subroutine_id`, `copy_object_assignment` — toggle whether the
   template/functionality assignment comes along), `task_rename_subroutine` (`from_subroutine_id`,
   `to_subroutine_id`), `task_delete_subroutine` (`subroutine_id`). Prefer these over hand-rebuilding a
   near-duplicate subroutine from scratch.

### Generation order (`subroutine.generation_order_no`)

When one subroutine's body calls another, the callee generally needs to exist first at generation time.
This matters more for **functions** than procedures: SQL Server's deferred name resolution lets
`create or alter procedure` succeed even referencing objects that don't exist yet (see the "successful
status is not proof the SQL is valid" note in `thinkwise_sf_control_procedures`),
but functions don't get the same leniency. Set `generation_order_no` so a subroutine that calls another
subroutine generates *after* the one it depends on, and confirm the dependency chain before assuming a
"Successful" generation status means the call actually resolved.

## Role rights

Every role needs an explicit grant to execute a subroutine — a `prog_object` existing and generating
cleanly says nothing about who can call it at runtime.

- **Where it lives**: `role_subroutine_overview.model_rights` (queryable directly, though
  it didn't surface through `get_entity_definition` in this session — query it directly rather than
  concluding it doesn't exist). Key: `model_id`, `branch_id`, `role_id`, `subroutine_id`. Fields:
  `granted` (bool — the actual toggle), `role_grp_id`/`role_grp_order_no`/`role_abs_order_no` (grouping/
  ordering for the rights screen), `rights_icon`.
- **One row already exists for every `(role, subroutine)` combination** — verified by reading rows
  across an entire model without filtering by `subroutine_id`. There's nothing to *add*; find the
  existing row for the target role/subroutine and flip `granted` to `true`.
- The `subroutine` entity's bound task `task_from_subroutine_to_subroutine_via_tab_modeler` (labelled
  "Go to Model rights") confirms this is the same screen reachable from the Subroutines modeler in the
  Software Factory UI — use it to cross-check, not as the only path.
- **Not independently verified**: whether a direct `patch_resource` against `granted` on this
  `*_overview` row succeeds, or whether — like `template_prog_object_item` in the control-procedures
  skill — it needs a bound task instead. Try the direct patch first; if it's rejected, look for a bound
  task on the row before concluding the right can't be granted through this API.
