# Running the creation pipeline as separate jobs

On both Indicium domain layouts, `task_add_job_to_do_complete_creation` cannot be used through the write API: its staged task comes
back as a variant (`creation_modeler`) that answers `staged_resource_type_not_found` on every property
write, so mandatory flags such as `sync_target_iam_id` can't be set or cleared — and its defaults run
every stage, including `run_sync`. Run each stage as its own job instead; this gives the same result
with a check between steps.

## The jobs, in order

| # | Stage | Task | Job type | Binding | Parameters |
|---|---|---|---|---|---|
| 0 | Set the upgrade source (only when it must change — see "Data migration mapping") | `add_job_to_update_data_migration_source_version` | 14 | Unbound | `select_data_migration_source_version_option` (0 runtime database, 1 branch version), `from_branch_id`, `runtime_configuration_id` |
| 1 | Generate definition | `add_job_to_generate_definition` | 0 | Unbound | `model_id`, `branch_id`, `error_handling`, `debug` |
| 2a | Validate — all | `task_add_job_to_validate_all` | — | Bound to `validation_modeler` — any row of the model (key `model_id, branch_id, id`; e.g. `id = 'access_control'`) | optional `validation_type` |
| 2b | Validate — one group | `task_add_job_to_validate_grp` | — | Bound to `validation_modeler` | `validation_grp_id`, `input_set` |
| 3 | Generate source code | `task_add_job_to_generate_code` | 2 | Bound to `code_generation` or to `code_generation_write_to_disk_overview` (there is no unbound variant) — bind to **any existing** row (even another model's) and overwrite `model_id`/`branch_id` in the parameters; re-read the fields before committing | `upgrade_method` (smart 0, full 1), `write_code_files_to_disk`, `write_prog_objects_to_disk` |
| 4 | Connect to the database | `connect_to_db` | 11 | Unbound | `model_id`, `branch_id`, `runtime_configuration_id`; optional `error_handling`, `host`, `db_name` |
| 5 | Execute source code | `add_job_to_execute_source_code` | 3 | Unbound | `model_id`, `branch_id`, `runtime_configuration_id` (host and database fill in from the runtime configuration), `error_handling` |
| 6 | Unit tests | `add_job_to_test_unit_test` | 4 | Unbound | `model_id`, `branch_id`, `runtime_configuration_id` |
| 7 | Smoke tests | `add_job_to_run_smoke_tests` | 15 | Unbound | as unit tests, plus `generate_smoke_tests` |

Use 2a for a full validation and 2b to re-run a single validation group; both exist, neither replaces
the other. `validation_modeler` rows exist only after a first definition generation on the branch.

Then sync to IAM (or create a deployment package) and restart/refresh the runtime as the change
requires.

- **Order is binding.** Code generation reads the **last generated definition**, not the live model.
  After any model change, rerun job 1 before job 3; otherwise the deployed procedures don't match what
  the GUI sends ("procedure … expects parameter '@x', which was not supplied").
- **`upgrade_method`:** `smart` (0) on a database that already holds data; `full` (1) for a first
  deployment to an empty database.
- Jobs 4–7 reach a live database — confirm with the user first, as for `execute_source_code`.
- Unit tests (job 6) need a database deployed for the runtime configuration; without one the job and
  its results are cancelled within seconds.

## Monitoring

| Job | Header entity | Done when |
|---|---|---|
| Generate definition | `definition_generation_overview` (`definition_generation_status_name`, `progress`) | status `Successful` (3) |
| Validate | `definition_validation_overview` | status `Successful` (3) |
| Generate code | `code_generation` (`code_generation_status`, `progress`) | status 3 |

Order by `job_id desc` and filter on the model to find the job you just started. **A completed job can
still have failed steps** — always read `definition_generation_step` after the job finishes, not only
the job's own status.

For the connect/execute jobs:

- The connect job's log (`execute_source_code_log`, keyed by the connect job id) says which path it
  took: "Database creation path enabled." (no database), "Table sf_model_info not found. Create
  enabled." (empty database), or "Database connection successful. Upgrade path enabled.". "An unknown
  error occurred while connecting." with a failed job means the host could not be reached.
- The execute job appends to the connect job's log. Each failed statement is logged as "An unknown
  error occurred while executing '<sql>'. Error: '<message>'."; template code carries
  `--control_proc_id: <id>` and `--template_id: <id>` comments that identify its source.
- `code_file_execution_overview` (`job_id` = the connect job, `execute_source_code_job_id` = the
  execute job) has an `execution_status` per code file (successful 3, failed 4).

## Reading validation results

`validation_msg` (filtered on `model_id`, `branch_id`) holds one row per finding, keyed by
`validation_id`; `pk_col_3` onward identify the object. Severity lives on `validation` (`severity`
0 = error); `validation_modeler` exposes the tree with `validation_type`. Query the error-severity
validation ids first, then look for messages with those ids — blocking findings are usually few among
hundreds of guideline/warning messages (unreviewed naming words, data-sensitivity choices, control
procedures still in development, duplicate icons from a linked icon model). Diagrams can't be written
through the API (see `thinkwise-sf-data-model`), so expect `val_tab_without_diagram_tab` for every new
table.

## Data migration mapping

The data migration mapping exists relative to the branch's **upgrade source**, set with
`add_job_to_update_data_migration_source_version` (job 0 above). Set the upgrade source before
generating the definition.

- `task_generate_data_migration` (bound to any `data_migration_tab` row) refreshes the mapping and
  renumbers every row (`data_migration_tab_no`, `data_migration_col_no`): look a row up by
  `to_tab_id`/`to_col_id` right before running a task on it, never reuse a number read earlier.
- `task_set_data_migration_tab` (bound to the new table's row, `from_tab_id`) fills a table from
  another; `task_set_data_migration_col` (`from_col_id`, or a default value) fills a column. Both
  create manual rows that survive regeneration.
- Renaming a table or column records a manual mapping row automatically.
- `data_migration_col` has no `model_id`/`branch_id` columns: scope queries on it by
  `to_model_id`/`to_branch_id`.
