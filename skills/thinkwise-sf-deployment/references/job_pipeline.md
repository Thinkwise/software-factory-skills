# Running the creation pipeline as separate jobs

Use this when the complete-creation task can't be parameterized through the API (its staged task
comes back as a variant that refuses further property writes, so mandatory flags such as
`sync_target_iam_id` can't be cleared or set). Each stage is also its own job, and running them one by
one gives the same result with a check between steps.

## The four jobs, in order

| # | Stage | Task | Binding | Parameters |
|---|---|---|---|---|
| 1 | Generate definition | `add_job_to_generate_definition` | Unbound | `model_id`, `branch_id`, `error_handling`, `debug` |
| 2 | Validate | `task_add_job_to_validate_all` | Bound to `validation_modeler` — any row of the model (key `model_id, branch_id, id`; e.g. `id = 'access_control'`) | optional `validation_type` |
| 3 | Generate source code | `task_add_job_to_generate_code` | Bound to `code_generation` — bind to **any existing** row (even another model's) and overwrite `model_id`/`branch_id` in the parameters; re-read the fields before committing | `upgrade_method`, `write_code_files_to_disk`, `write_prog_objects_to_disk` |
| 4 | Execute source code | `add_job_to_execute_source_code` | Unbound | `model_id`, `branch_id`, `runtime_configuration_id` (host and database fill in from the runtime configuration), `error_handling` |

Then sync to IAM (or create a deployment package) and restart/refresh the runtime as the change
requires.

- **Order is binding.** Code generation reads the **last generated definition**, not the live model.
  After any model change, rerun job 1 before job 3; otherwise the deployed procedures don't match what
  the GUI sends ("procedure … expects parameter '@x', which was not supplied").
- **`upgrade_method`:** `smart` (0) on a database that already holds data; `full` (1) for a first
  deployment to an empty database.
- Job 4 runs SQL against a live database — confirm with the user first, as for `execute_source_code`.

## Monitoring

| Job | Header entity | Done when |
|---|---|---|
| Generate definition | `definition_generation_overview` (`definition_generation_status_name`, `progress`) | status `Successful` (3) |
| Validate | `definition_validation_overview` | status `Successful` (3) |
| Generate code | `code_generation` (`code_generation_status`, `progress`) | status 3 |

Order by `job_id desc` and filter on the model to find the job you just started.

## Reading validation results

`validation_msg` (filtered on `model_id`, `branch_id`) holds one row per finding, keyed by
`validation_id`. Severity lives on `validation` (`severity` 0 = error); `validation_modeler` exposes the
tree with `validation_type`. Query the error-severity validation ids first, then look for messages with
those ids — blocking findings are usually few among hundreds of guideline/warning messages (unreviewed
naming words, data-sensitivity choices, control procedures still in development, duplicate icons from a
linked icon model).
