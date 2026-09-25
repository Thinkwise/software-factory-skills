# Worked example — idempotent demo-data seed in `ug_after_upgrade_always`

Loaded on demand from `thinkwise_sf_control_procedures`.

### Worked example: idempotent demo-data seed woven into `ug_after_upgrade_always`

Verified end-to-end on a from-scratch model — the pattern for a re-runnable seed/demo-data script
that fires on every deploy/upgrade and only inserts what's missing (the platform's own
`seed_demo_data*` convention):

1. `control_proc` — `code_grp_id = UPGRADE`, `control_proc_type = 1` (program_object_item),
   `assign_type = 0` (static), staged under `branch` per step 3 above.
2. `control_proc_template` — one template; set `template_description` first, `template_code`
   (the T-SQL) last in the same call. The body upserts reference rows with
   `if not exists (select 1 from <t> where <natural key>) insert …` and gates bulk/child tables on
   `if not exists (select 1 from <t>) begin … end`; all dates relative to `cast(getdate as date)`
   so the seeded data always looks current.
3. `template_prog_object_item` — direct add: `rdbms_type` (per platform),
   `prog_object_id = 'ug_after_upgrade_always'`, a unique `prog_object_item_id`, `control_proc_id`,
   `template_id`, and an `order_no` after any existing seed items (e.g. `100`).
4. `task_generate_code_grp` bound to your *own* `control_proc` — materialises/refreshes
   `prog_object_item` so the assignment is picked up.
5. `task_add_job_to_generate_object_code` on `prog_object_code` for
   `(model_id, branch_id, rdbms_type, prog_object_id = 'ug_after_upgrade_always')`.
6. Re-read `prog_object.generated_code_stale` (should be `false`) and the
   `prog_object_generated_code` text — confirm your seed block is actually present (indented as a
   fragment, no `create`/`alter` wrapper — `ug_after_upgrade_always` is woven into the master
   upgrade script), not just that generation returned "successful".

Deploying the database is still a separate pipeline step (see
`thinkwise_sf_deployment`); generating only updates the model.
