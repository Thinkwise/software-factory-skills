# Assignment types, static assignment entities, and the two-task generation sequence

Loaded on demand from `thinkwise_sf_control_procedures`.

## Assignment types

- **Static**: Assigning tab → search the task/view/subject/column/other object → attach the
  template → fill `[PARMTR]` values. Check "Ignore if empty" on a parameter to drop that line
  entirely when no value is given, instead of emitting an empty string.
- **Dynamic (SQL)**: write into the staging tables backing `prog_object`, `prog_object_item`, and
  `prog_object_item_parmtr`. A parameter can fan out into multiple rows (e.g. one line per column in
  a table) — the main reason to reach for SQL assignment over static.
- `[PARMTR]` parameters auto-generate on the Parameters tab the moment they're typed into a
  template; an icon flags any still missing a value. Run **Generate parameters** if they didn't
  appear automatically.

### Static assignment via API — the actual entities involved

`control_proc_template.type_of_object`/`object_id` look like the assignment mechanism, but static
assignment for column-level logic (Default, Layout, Context, …) is wired through a different pair:

- **`template_prog_object_item`** — the actual junction. Key
  `(model_id, branch_id, rdbms_type, prog_object_id, prog_object_item_id)`; scalars `control_proc_id`,
  `template_id`, `order_no`. One row = "this template contributes code, at this position, inside this
  generated program object" (`prog_object_id = 'default_absence'` is the table's whole generated
  Default procedure). `prog_object_item_id` need only be unique per `(rdbms_type, prog_object_id)` —
  reusing `template_id` as the item id is a reasonable default.
  Naming extends to tasks, not just tables: `task_<task_id>`, `default_<task_id>`, `layout_<task_id>`,
  `badge_<task_id>`.

  **Ordering.** All templates on one `prog_object_id` concatenate into a single procedure body in
  `order_no` order, so a variable declared in a low-`order_no` template is visible to a high-`order_no`
  one — a legitimate way to carry a row's pre-mutation state forward. Framework wrapper items bookend
  your own (`defaults_start`/`defaults_end` at 1 and 100000); on a Handler you can bracket the
  framework's own generated statement with a low-`order_no` (pre-mutation validation) and a
  high-`order_no` (post-mutation follow-up) template.
  **Never give a custom item the same `order_no` as a framework wrapper item** (typically `1` for a
  Handler's `handler_start`). Ties break **alphabetically by `prog_object_item_id`**, not by intent —
  a custom id sorting before the wrapper renders ahead of the procedure's own header and parameter
  list, referencing out-of-scope parameters, and **fails at deploy time, not at generation time.**
  Query `prog_object_item` for the target first to see the wrapper `order_no`s (e.g. `handler_start` 1,
  `transaction_start` 2, the generated statement ~1000) and pick a value strictly between two of them
  — e.g. `5`.
  **A pre-mutation template runs before the framework has opened its transaction** — a bare
  `rollback transaction` there errors with nothing to roll back. Guard it:
  `if @@trancount > 0 rollback transaction`.
- **`template_prog_object_item_parmtr`** — child of the above (same compound key plus
  `prog_object_item_parmtr_id`, auto int64). Holds `parmtr_id`/`parmtr_value` pairs: `parmtr_id` must
  match a `[bracket_token]` used literally in `template_code` (case-sensitive, bare name, no `@`),
  `parmtr_value` is the literal text substituted at generation time.
- `prog_object` rows already exist once the table has ever been generated — check before assuming a
  Generate-code-group pass is needed.
- **A direct add to `template_prog_object_item` usually works, but can be rejected on some
  connectors.** Try the direct add first. If it errors, mirror the Assigning screen instead: find the
  read-only "available templates" overview row for the target `(rdbms_type, prog_object_id,
  control_proc_id)` and invoke its bound add-assignment action for the specific `template_id` — it
  writes the same junction row through a task.
  **Confirm the add from the response's `fields` block, not its `signals`:** a successful add can list
  `cleared_fields` naming `branch_id`/`control_proc_id`/`template_id`/`prog_object_id` while `fields`
  shows all of them correctly set. That is lookup re-resolution during staging, not a real drop.
- **A direct edit to `order_no` can be rejected the same way.** Same fallback one level down: the
  *assigned*-templates overview row (keyed by `rdbms_type`/`prog_object_id`/assigning
  `control_proc_id`/`prog_object_item_id` — distinct from the "available templates" overview used for
  adding) exposes `order_no` as a plain editable field.
- **Generating code is two distinct tasks, not one** — see below before calling either. A single
  `task_generate_code_grp` call does *not* regenerate `prog_object_generated_code` for a brand-new
  object.

### Actually generating code — two distinct tasks, don't conflate them

Generating code is **two separate tasks**. Running only the first produces no code and no error.

1. **`task_generate_code_grp`, bound to `control_proc`** — address it with
   `(model_id, branch_id, control_proc_id)`; no `prog_object_id` needed. Use any control procedure in
   the target code group — your own, or the group's framework meta procedure (e.g. `pg_views` for
   `VIEWS`). It **materializes the missing `prog_object` placeholder row**, which nothing else can
   create: `prog_object` itself returns `403` on add, and step 2 needs a `prog_object_id` that doesn't
   exist yet.
   **This step does not generate code.** After it, `generated_code_stale` is still `true`,
   `prog_object_generated_code` is still empty, and nothing is queued. Its only job is to make the
   object addressable.
   A commit of this task can report a **transport-level timeout while having succeeded server-side** —
   re-query for the expected row before retrying or working around it.
2. **`task_add_job_to_generate_object_code`, bound to `prog_object_code`** (or `prog_object_overview`)
   — address it with `(model_id, branch_id, rdbms_type, prog_object_id)`, now resolvable. This is what
   actually queues the job and produces code.
   - The job lands in `generate_object_code` (key `job_id`; `generate_object_code_status` byte enum:
     `scheduled` 0, `executing` 1, `wait_for_user` 2, `successful` 3, `failed` 4, `cancelled` 5,
     `aborted` 6, `warning` 7, `info` 8, plus a readable `generate_object_code_status_name`). There is
     no timestamp field — use `$orderby=job_id desc`.
     **This entity set may not resolve on every connector** (some expose only
     `generate_object_code_log`: `job_id`/`error_no`/`error_msg`, no status). Don't hunt for it by
     name; use the check below instead, which is sufficient on its own.
   - **Confirm output by re-reading the `prog_object` row**: `generated_code_stale` should be `false`
     and `prog_object_generated_code` should hold real SQL.
   - **`prog_object.control_proc_id` does not tell you whose logic is in there.** It reflects whichever
     control procedure owns the code group's structural wrapper, regardless of what you assigned or
     what triggered generation. This misleads in both directions — confirming your own assignment
     landed, *and* finding the real owner of existing logic you want to edit.
     **The reliable route both ways: read `prog_object_generated_code` itself.** Its header comments
     (`--control_proc_id:`, `--template_id:`, `--prog_object_item_id:`) name the actual control
     procedure and template behind each section; look those up in
     `control_proc`/`control_proc_template`.
3. **Step 1 is only needed once per brand-new object.** Once a `prog_object` row exists, go straight
   to step 2 for every later template or assignment change.
4. **`prog_object` is not directly writable** — add returns `403`. Always go through step 1.
5. **Known gap — a brand-new *standalone* subroutine** (`PROCEDURES`/`FUNCTIONS`/
   `TABLE_VALUED_FUNCTIONS`) with no table/view/task to hang off may never get its placeholder
   materialized. Both `task_generate_code_grp` bound to the group's framework procedure and an unbound
   whole-branch "generate new objects" task left no `prog_object` row and raised no error. The control
   procedure, template and SQL can still be authored via the API; only the deployable object can't.
   Treat it as a manual generate pass in the Software Factory, and say so, rather than retrying
   alternate API paths.
6. **After wiring a new `template_prog_object_item` onto an object whose placeholder was bootstrapped
   in step 1 with a *different* (e.g. framework) control procedure, re-run step 1 bound to your own
   control procedure before step 2.** Otherwise generation reports `successful` with
   `generated_code_stale = false`, but the code contains only the framework's `_start`/`_end` wrapper
   fragments — your template's logic is silently missing, because `prog_object_item` hadn't re-synced.
   **A `successful` status is not proof the right logic made it in** — read the generated text and
   confirm your template's content is present.

### Reuse — decide in this order

Before writing anything new: reuse an existing template across assignments rather than duplicating it;
add a *second* template to an object that already has a large one rather than editing the existing
body; and remember a just-created table/view/task has no `prog_object` to assign to until it has been
generated once (see above).

For the full decision order, the multi-assignment reuse patterns, and how the generated code's
comment header (`--control_proc_id:`, `--template_id:`, `--prog_object_item_id:`) round-trips back to
the owning template, read `references/reuse_and_round_trip.md`.
