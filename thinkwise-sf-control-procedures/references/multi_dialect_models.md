# Working on a multi-dialect (multi-RDBMS) model

Loaded on demand from `thinkwise_sf_control_procedures`.

### More than one row returned → the shape of the work changes, not just the SQL text
1. **One dialect-specific `control_proc_template` per platform.** `control_proc_template`'s key
   (`model_id, branch_id, control_proc_id, template_id`) does **not** carry `rdbms_type` — give each
   platform's version of the logic its own `template_id` (e.g. `<name>_mssql` / `<name>_pg`, or reuse
   one `control_proc_id` with distinct `template_id`s per platform). Never write one template whose
   literal text merely happens to parse on two engines through escaping tricks — that's this exact bug
   waiting to resurface the moment one engine's syntax drifts from the other's.
2. **One `template_prog_object_item` row per `(rdbms_type, prog_object_id)`.** This junction's key
   already includes `rdbms_type`, so wire each platform's `prog_object_id` (the same logical object,
   e.g. `view_<tab_id>`, but a distinct row per `rdbms_type`) to its matching dialect-specific
   `template_id` from step 1. One assignment cannot serve two platforms.
3. **Generate and verify for every enabled `rdbms_type` separately** — both halves of "Actually
   generating code" below (`task_generate_code_grp` then `task_add_job_to_generate_object_code`) are
   addressed per `rdbms_type`. A `prog_object` existing, or generation succeeding, for one platform
   says nothing about the others. Before considering the work done: query
   `/prog_object?$filter=model_id eq '<model>' and branch_id eq '<branch>' and tab_id eq '<tab>'
   &$select=rdbms_type,generated_code_stale` and confirm a row exists with `generated_code_stale =
   false` for **every** `rdbms_type` `branch_rdbms_type` returned — then read
   `prog_object_generated_code` for each and eyeball that it's actually in the right dialect (right
   date functions, right paging syntax, right identifier quoting), not just that it generated without
   an error.
4. **Assignment can't be made "generic" to save a step.** Once there's more than one dialect, a Static
   assignment or a `template_prog_object_item` row is inherently platform-specific — resist assigning
   the same template to every platform's `prog_object_id` just because the ids/rows look interchangeable.

See "`rdbms_type` — when it's actually required" further below for the same key's role specifically in
SQL-assigned/dynamic model procedures — this section is the general version, and applies to *every*
control procedure, static or dynamic, the moment real SQL is involved.
