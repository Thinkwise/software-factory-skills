# Step-by-step: creating a subroutine, options, and role rights

Loaded on demand from `thinkwise-sf-subroutines`.

## Step-by-step: creating a subroutine

1. **Query `branch_rdbms_type`** (see `thinkwise-sf-control-procedures`) before
   anything else — it determines both the buildable `subroutine_type` set and the SQL dialect the body
   will be written in.
2. **Create the `subroutine` row**: `subroutine_id` (name for purpose, see "Naming" below),
   `subroutine_type_id` (from the live `subroutine_type` list), `return_value`, and
   `return_scalar_dom_id`/`return_table_id` to match. Leave `api`/`basic_api` off until the contract is
   stable (see "Publishing as an API" below). For a Procedure, decide `single_transaction` now (see
   "Transaction behavior"); it applies to procedures only.
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
   - **Order matters for the placeholder**: the `subroutine` row and its `subroutine_parmtr` rows first,
     then the control procedure in its code group, then `task_generate_code_grp` bound to that control
     procedure (step 8). Assign the template at `order_no` 10. A procedure's framework wrapper items are
     `procedures_start` at 1 and `procedures_end` at 100000, plus `transaction_start` at 2,
     `transaction_catch` at 99099 and `transaction_end` at 99999 when `single_transaction` is set
     (procedures only).
   - **The real generated database object name is the bare `subroutine_id`**, no prefix — confirmed by
     reading a generated function's text (`create or alter function "tsf_user" (...) ...`). Don't
     expect `func_`/`proc_` to appear in the deployed SQL.
   - **`control_proc_type = 1` (`program_object_item`), `assign_type = 0` (Static)** is the normal shape
     for a subroutine's own hand-written body — one control procedure, one template, one
     `template_prog_object_item` row pointing at `func_<id>`/`proc_<id>`, exactly as documented in
     `thinkwise-sf-control-procedures`'s "Creating and assigning a control
     procedure — step by step" section. Follow that section verbatim from here, including its dialect
     checklist and the "leave the template blank, generate first to see the real scaffold" step.
   - **Business-logic variables inside the body are just the subroutine's own declared parameters** —
     `@[subroutine_parmtr_id]` in T-SQL (`p_[subroutine_parmtr_id]` in PostgreSQL), not one of the
     Default/Layout/Handler-style variable sets in that skill's `references/code_type_variables.md`.
     There's no separate "input/output variable" table for subroutines because the parameter list *is*
     the variable list.
8. **Generate and verify** — same two-task flow as any other code type
   (`task_generate_code_grp` → `task_add_job_to_generate_object_code`, confirmed via
   `generate_object_code_status`/`generated_code_stale`, then read the generated text). Bind
   `task_generate_code_grp` to the subroutine's own control procedure; it materializes
   `func_<id>`/`proc_<id>` (verified live on PostgreSQL and SQL Server). If no `prog_object` row appears
   anyway, treat the generate as a manual step in the Software Factory (see
   `thinkwise-sf-control-procedures`, assignment and generation).
9. **Copy / rename / delete** — all bound tasks on `subroutine`, verified: `task_copy_subroutine`
   (`from_subroutine_id`, `to_subroutine_id`, `copy_object_assignment` — toggle whether the
   template/functionality assignment comes along), `task_rename_subroutine` (`from_subroutine_id`,
   `to_subroutine_id`), `task_delete_subroutine` (`subroutine_id`). Prefer these over hand-rebuilding a
   near-duplicate subroutine from scratch. A direct delete of the `subroutine` row removes its
   parameters and assignment but leaves `proc_<id>`/`func_<id>` behind until the next generation.

### Generation order (`subroutine.generation_order_no`)

When one subroutine's body calls another, the callee generally needs to exist first at generation time.
This matters more for **functions** than procedures: SQL Server's deferred name resolution lets
`create or alter procedure` succeed even referencing objects that don't exist yet (see the "successful
status is not proof the SQL is valid" note in `thinkwise-sf-control-procedures`),
but functions don't get the same leniency. Set `generation_order_no` so a subroutine that calls another
subroutine generates *after* the one it depends on, and confirm the dependency chain before assuming a
"Successful" generation status means the call actually resolved.

## Role rights

Every role needs an explicit grant to execute a subroutine — a `prog_object` existing and generating
cleanly says nothing about who can call it at runtime.

- **Where it lives**: `role_subroutine_overview` (variant `role_subroutine_overview.model_rights`).
  Key: `model_id`, `branch_id`, `role_id`, `subroutine_id`. `granted` is the toggle; `super_user` and
  `rights_icon` show why a row is granted.
- **One row already exists for every `(role, subroutine)` combination** — there's nothing to *add*;
  find the existing row for the target role/subroutine and flip `granted` to `true`, by a direct edit
  or the bound task `task_role_subroutine_set_rights` (Assign rights).
- **A super-user role is granted automatically** (`super_user = true`, `rights_icon` 1) — grant only
  the other roles that call the subroutine.
- The `subroutine` entity's bound task `task_from_subroutine_to_subroutine_via_tab_modeler` (labelled
  "Go to Model rights") opens the same screen in the Software Factory UI.
- For the general rights mechanics (resending an unchanged value, what read access grants), see
  `thinkwise-sf-roles`.
