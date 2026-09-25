# Task look-ups and form setup

Loaded on demand from `thinkwise_sf_tasks`.

## Task look-ups (`task_ref` / `task_ref_col`)

Reach for a custom look-up whenever a parameter's own domain doesn't already point at the right
table, or the default look-up behaviour isn't what's wanted:

- A different table, or a specific **table variant** (`look_up_tab_variant_id`) rather than the
  default one.
- A different **display column** (`look_up_display_col_id`) than the table's own default.
- A different **look-up control**: `auto_complete` (0), `combo_alphabetical` (1),
  `combo_sorted` (4), `suggestion_contains` (2), `suggestion_starts_with` (3).
- A **popup picker** (`look_up_has_popup`) instead of an inline combo/suggestion field.
- A **composite** look-up spanning multiple columns — `task_ref_col` maps each contributing
  `(tab_id, col_id)` to the parameter(s) it feeds, in order (up to nine columns via the
  `task_create_task_ref` bound task's `col_id_1..9`/`task_parmtr_id_1..9` parameters).

Create one either standalone against `task_ref` (+ a `task_ref_col` child row per contributing
column), or directly from the owning task via `task_create_task_ref` (bound to `task`) — in principle
both take the same shape. **`task_create_task_ref` proved unreliable in practice**: staging
it succeeded, but the very next call against the returned staged resource failed with a
"type not found"-style rejection, even though nothing about the request looked malformed. The
standalone `task_ref`/`task_ref_col` add flow for the identical look-up succeeded without issue.
Default to the standalone flow rather than the bound task, and treat `task_create_task_ref` as
suspect if it's ever reached for again. `task_modify_task_ref` edits a look-up afterward. Per-task-variant
overrides live in `task_variant_look_up_overview`, with its own reset-to-base action
(`task_reset_task_variant_look_up_overview`).

## Form setup: four mechanisms, easy to conflate

They differ on two axes — **static vs. dynamic**, and **cosmetic vs. behavioural**:

| Mechanism | Static/dynamic | What it does | Reach for it when… |
|---|---|---|---|
| **Groups** (`form_next_grp_label`/`next_tab_label` on `task_parmtr`) | Static | Pure visual grouping/sectioning. No logic. | The form just needs organizing into labelled sections — always the first tool. |
| **Conditional layout** (`task_conditional_layout`) | Static, condition-gated | No-code font/colour styling triggered when a stated condition on a parameter is true. | The need is purely cosmetic emphasis (e.g. highlight a value past a threshold), not a real show/hide/mandatory change. |
| **Layout concept** (`task.use_layouts` + a Layout control procedure) | Dynamic (runtime SQL) | Real-time control of a parameter's visibility (`@[parmtr]_type`: normal/read-only/hidden-in-form/hidden-outside-form) and mandatory-ness, plus Confirm/Cancel button types — reacts to `@layout_mode`/`@cursor_from_col_id` and other parameters' current values. | Fields must actually appear, disappear, or become mandatory based on other input on the same form. |
| **Defaults concept** (`task.use_defaults` + a Default control procedure) | Dynamic (runtime SQL) | Computes a parameter's value — once on open, or reactively per edit — via `@default_mode`/`@cursor_from_col_id`. | A parameter's value should be derived, not typed (a constant or `default_value_query` on the parameter itself is the lighter option for trivial logic). |

**Don't pick unilaterally when it's a close call.** This table is for the clear-cut cases. If it's not
obvious from the request which mechanism(s) actually apply — e.g. it could plausibly be cosmetic
Conditional layout or a real behavioural Layout change — ask the user rather than choosing on their
behalf; this is exactly the kind of choice "Plan first" above should surface before any staging call.

The Task code type reuses the **same** Default/Layout business-logic variables tables/rows do, just
scoped to a task parameter instead of a column (`@[task_parmtr_id]` in place of `@[col_id]`) — see
`thinkwise_sf_control_procedures`'s `references/code_type_variables.md` for
the exact per-direction variable names before writing the template body.

### Consider `task_conditional_layout` for new parameters — but only where it's warranted

After adding a task's parameters, take one pass asking whether **conditional layout** (cosmetic
font/colour styling on a parameter, triggered by a condition on it or another parameter — see the table
above) would genuinely help this specific form: a parameter whose value can exceed a threshold, a
destructive option that's been selected, a required field still empty, a date outside a sensible
window. **Only add one where there's a real candidate — don't add one just because a task has
parameters.** Plenty of tasks (a plain confirm/cancel action, a simple lookup-and-submit form) have
nothing worth highlighting; say so and add nothing rather than inventing a marginal one.

**Never add a `task_conditional_layout` without checking with the user first** — present the candidate
parameter(s), the condition, and what it would communicate, and get explicit confirmation before
creating anything. If this task is part of a larger plan (e.g. from `thinkwise_sf_build_planner`),
fold the candidate into that plan and get the **plan** confirmed before finalizing it, not as a silent
addendum once the task is being built.

For the actual mechanics — field reference, the condition enum, `task_variant_task_conditional_layout`
per-variant overrides, and known gaps — see `thinkwise_sf_conditional_layouts`. This
section only decides *whether* one is warranted; that skill covers *how* to build it.

**Both gates, every time**: the task-level `use_layouts`/`use_defaults` flag on `task` *and* the
parameter-level `layout_input`/`layout_type_output`/`layout_mand_output` or
`default_input`/`default_output` flags on `task_parmtr` must be on. An assigned template with
either gate off generates without error and simply never fires — the exact same trap the
control-procedures skill documents for table columns applies here.
