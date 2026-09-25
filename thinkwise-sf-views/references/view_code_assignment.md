# Writing and assigning a view's SELECT code (Template method)

Loaded on demand from `thinkwise_sf_views`.

## Writing and assigning code to a view (Template method)

This is the verified, concrete object chain behind every Template view in a production model, traced
end-to-end via the Software Factory metadata API:

`tab` (view) → generation produces a structural `prog_object` named `view_<tab_id>`, owned by the
framework's `VIEWS`-code-group meta control procedure → your own `control_proc` supplies the actual
`SELECT` as a fragment woven into that `prog_object` via a `template_prog_object_item` row.

1. **Query `branch_rdbms_type`** (`/branch_rdbms_type?$filter=model_id eq '<model>' and branch_id eq
   '<branch>'` — see the control-procedures skill's "Check `branch_rdbms_type` first" section) before
   writing anything. One row → write the view's `SELECT` in that platform's dialect. More than one row
   → this view needs one dialect-specific `control_proc_template` per platform and one
   `template_prog_object_item` per `(rdbms_type, prog_object_id)` — decide this now, it changes steps 3
   and 5 below, not just the SQL text in step 4. Skipping this is exactly how a view ends up with
   `getdate`/`dateadd`/`select top n` generated against a PostgreSQL-only model, or `limit`/`age`
   generated against a SQL-Server-only one — every write along the way still reports success either
   way, so this has to be checked up front, not diagnosed after the fact.
2. **Model the view's columns first** (above) — order, primary key, domains. The `SELECT` written in
   step 5 must produce exactly this column list, in this order, with matching aliases.
3. **Make sure the view's structural program object exists.** A brand-new view has no generated
   program objects yet. Run **Generate code group** for the `VIEWS` code group (`task_generate_code_grp`,
   bound to `control_proc`, addressable by just `(model_id, branch_id, control_proc_id)` — use any
   control procedure already in `VIEWS`, e.g. the framework's own `pg_views`, since your own control
   procedure for this view doesn't exist yet at this point) once so the framework's `view_<tab_id>`
   program object shell exists — nothing can be attached to it before that. **This only creates the
   placeholder row — it does not generate any code yet**; see step 6 and the
   `thinkwise_sf_control_procedures` skill's "Actually generating code" section
   for why that's a second, separate task. Multi-dialect models: this creates one `prog_object` row per
   enabled `rdbms_type` for the same `tab_id` — expect (and plan to fill) all of them, not just one.
4. **Business Logic → Functionality → Control procedures → New** (`control_proc` entity):
   - `code_grp_id = VIEWS`
   - `control_proc_type = program_object_item` (the code is a *fragment* woven into the generated
     `CREATE VIEW` object, not a standalone object)
   - `assign_type = static` (one view = one hand-picked assignment; SQL/dynamic assignment is for
     framework-internal or genuinely repeating patterns, not a one-off view query)
   - ID: match the view name, or the model's chosen prefix convention (above). Multi-dialect: either
     one `control_proc` with one `control_proc_template`/`template_id` per platform, or a distinct
     `control_proc` per platform — pick one convention and hold to it across the model, same as any
     other naming decision here.
5. **Add a `control_proc_template`, but leave `template_code` blank at first** and regenerate — this
   surfaces the real scaffold instead of guessing at it. **Caveat**: `template_code`
   can be enforced as mandatory by the write API in use, rejecting a true empty string — if so, use a
   short placeholder (e.g. `-- placeholder`) to get past the check, then overwrite it with the real
   `SELECT` once the scaffold has been seen. Then write the full `SELECT`, **in the
   dialect(s) confirmed in step 1**:
   - Column list matches the view's modeled columns, in order, aliased to the exact `col_id`s.
   - Grep a sibling view's template in the same model — and the same `rdbms_type`, if multi-dialect —
     for join style, alias conventions, paging syntax (`limit` vs. `top`), date/time functions, and
     comment-header style before introducing a new one — consistency beats individual preference (see
     the style-continuity rule in the control-procedures skill).
   - Follow the general Thinkwise SQL guidelines (see the control-procedures skill): lowercase
     keywords, explicit column lists, no `SELECT *`, comment non-obvious joins/filters, avoid
     `DISTINCT` where a `GROUP BY` does the same job more explicitly.

   ```sql
   -- Example shape, adapted from a real production view template (PostgreSQL dialect)
   select  c.customer_code
,cd.company_no
,c.customer_short_name
,c.customer_group
,cd.customer_type_id
   from    customer c
   join    customer_detail cd
       on  cd.customer_code = c.customer_code
   where   c.active = 1
   ```
6. **Wire the template into the generated view object.** Two equivalent routes (same mechanism as
   any other static assignment — see the control-procedures skill's "Static assignment via API"
   section for the full entity/field breakdown):
   - **UI**: Functionality → Assigning tab → find the view's program object → attach the template.
   - **API/dynamic**: insert a `template_prog_object_item` row — `prog_object_id = 'view_<tab_id>'`,
     `control_proc_id`/`template_id` = the new control procedure/template, `order_no = 10` (leaves
     room to insert more fragments later, e.g. a second comment block or a `UNION` branch).
     Multi-dialect: one such row **per `rdbms_type`**, each pointing `prog_object_id`'s `rdbms_type`
     at the matching dialect-specific `template_id` from step 5 — never point two platforms' rows at
     the same template.
7. **Generate the actual code — two distinct tasks, don't conflate them.** See the
   `thinkwise_sf_control_procedures` skill's "Actually generating code" section
   for the full generate-code-group vs. generate-object-code walkthrough, including the
   placeholder/re-run gotcha (a brand-new static assignment needs `task_generate_code_grp` re-run
   against *your* control procedure, not just the framework one from step 3, or the generated body
   silently keeps only the wrapper) — that mechanic is generic to any `program_object_item` control
   procedure, not specific to views. What's specific to views:
   - The generated program object is always named `view_<tab_id>`. Target
     `task_add_job_to_generate_object_code`'s `prog_object_code` key at
     `(model_id, branch_id, rdbms_type, prog_object_id = 'view_<tab_id>')`.
   - After generation, re-read the `prog_object` row and sanity-check
     `prog_object_generated_code` against intent (column list, joins, filters match what was modeled)
     **and against the dialect confirmed in step 1** (right date/time functions, paging clause,
     identifier quoting) — a clean generate says nothing about dialect correctness by itself. If the
     view replaces an ad hoc query (below), diff the generated SQL's logic against that original query
     directly.
   - **Multi-dialect: repeat generation and the read-back for every `rdbms_type` in
     `branch_rdbms_type`**, not just the first one that works. Query
     `/prog_object?$filter=... and tab_id eq '<tab>'&$select=rdbms_type,generated_code_stale` and
     confirm `generated_code_stale = false` for all of them before considering the view done.
   - This is as far as this skill goes — deploying the generated code to a database is a separate step
     outside its scope, and `prog_object` isn't directly writable through this API either — don't
     assume a successful generate means deploy is also possible; confirm with the user first.
8. **Validate / code review as normal** — move `development_status` through review, attach unit
   tests if the view feeds anything business-critical (a report, a financial calculation, a process
   flow decision).
