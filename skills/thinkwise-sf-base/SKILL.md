---
name: thinkwise-sf-base
description: Base check to run before doing real work through any MCP connector that provides Thinkwise Software Factory access. Confirms which connector, which application model, and which branch (model_id/branch_id) apply, since one Software Factory repository commonly hosts several application models with multiple branches each and most entities are keyed by model_id/branch_id. Use once near the start of a task, not before every individual tool call.
---

# Software Factory MCP base check

Three things have to be pinned down before real Software Factory work starts: **which connector**,
**which application model**, and **which branch**. All three are easy to get wrong silently — a
query with no explicit `model_id`/`branch_id` filter can match rows from an entirely different
model or branch in the same shared repository (see `thinkwise_sf_data_model`). Run this
check once per task, before the first substantive read/write call, not on every tool call.

## Terminology — never call it "Studio"

The Thinkwise design-time modeling tool — where a developer edits tables, tasks, maps and control
procedures outside any MCP connector — is **the Software Factory**. **Never call it "Studio"**; that
name appears in no Thinkwise documentation or terminology. When a manual step is needed outside what a
connector can reach, say "the Software Factory" (or "the Software Factory's GUI Modeler" for a specific
screen).

## 1. Which connector

Look at the connected MCP servers that expose the Software Factory toolset (tool names like
`get_domain_definition`, `execute_odata_query`, `stage_resource` — e.g. `sf_mcp`, `meta_dev`,
`indicium`, or a differently-named instance).

- **Exactly one such connector connected** → use it, don't ask.
- **More than one**, and the user's request doesn't already name one → ask which one via
  AskUserQuestion, listing the connector names as options.
- If the user's message already names or implies the connector, use that — don't ask again.

## 2. Which application model

A repository can hold multiple application models (e.g. `RK_MERIDIAN`, `RK_SCHEDULER_TEST`,
`INSIGHTS`), each scoped by its own `model_id`. Only ask about this when the task actually touches
model-specific data (tables, tasks, screens, control procedures, process flows, etc.) — pure
metadata/discovery calls like `search_capabilities` don't need it yet.

- If the user's message, or anything earlier in this conversation, already names the application
  model (or it's unambiguous from context, e.g. only one model exists in the repository) → use
  that, don't ask.
- Otherwise, list the distinct `model_id` values available through the chosen connector (e.g. a
  grouped query on `branch`, with description) and ask the user to pick via AskUserQuestion. Skip
  the ask if that query turns up only one model.

## 3. Which branch

Once the application model is settled, the same repository query also carries `branch_id` —
each model typically has more than one branch (e.g. a mainline plus feature/test branches).

- If the user's message, or anything earlier in this conversation, already names the branch (or
  only one branch exists for the chosen model) → use that, don't ask.
- Otherwise, list all branches for the chosen `model_id` (e.g. filter that same `branch` query by
  `model_id`) and ask the user to pick via AskUserQuestion, showing every branch found.

## Once resolved

Treat the chosen connector, `model_id`, and `branch_id` as pinned for the rest of the task — carry
them into every subsequent `execute_odata_query`/`stage_resource`/`stage_task` filter and
parameter, and don't re-ask unless the user switches context to a different model, branch, or
connector.

## Shared conventions every other Software Factory skill builds on

Every `thinkwise_sf_*` skill inherits these rules **instead of restating them**. Where a
skill's own text conflicts with these, follow these.

- **Confirm-before-mutate.** Before the *first* `stage_resource`/`stage_task`/`patch_resource`/
  `commit_resource` call for a piece of work, state the concrete plan in plain language — what will be
  created/changed, the key design choices, and how it fits the existing model — and get explicit
  confirmation. Scope the plan to the work's real grain: a multi-artifact goal gets one bundled plan
  (`thinkwise_sf_build_planner`); a single artifact gets a short plan covering its own
  design decisions, not mechanical CRUD steps. Skills with their own propose→confirm process
  (build_planner, unit_tests) already satisfy this.
  **Answering clarifying sub-questions is not that confirmation.** If the plan changes afterward for
  any reason — new information, the branch's RDBMS ruling out a proposed type, scope moving —
  re-present the complete updated plan and get an explicit go-ahead on *that* before the first
  mutating call.
- **Ask, don't default.** When a design choice isn't dictated by the user's words or an unambiguous
  read of the live model, ask rather than picking a default and iterating afterward. This overrides
  any instruction anywhere in this skill set phrased as "default to X unless the user says otherwise"
  — treat such a line as *what to propose when you ask*, never as license to apply it silently.
- **Plan as numbered steps, and report progress against them.** Express the plan as an ordered,
  numbered list, not a prose paragraph. After each step, post a one-line status update — step just
  finished, next step, percent complete — e.g. `Step 3/8 done — menu groups created · next: menu
  items · ~38%`.
  **A progress update is not a stopping point.** Once the plan is approved, execute it in *one
  continuous run*. Emit each status line inline as it completes, **and** repeat the running trail in
  the turn's final message — some display modes show the user only that final message, so the closing
  summary must carry the full step-by-step account, not just "all done".
  Work straight through the approved plan — or, if the user scoped the request to specific steps,
  only those. **The only legitimate mid-build stops** are (a) an unrecoverable blocker (an error you
  cannot resolve, missing access) or (b) a design decision that surfaces mid-build and isn't settled
  by the approved plan — including the plan itself needing to change, which means re-present and
  re-confirm. A status line, a finished step, or ordinary uncertainty you can resolve with a
  recommended call are *not* reasons to stop.
- **Verify unfamiliar field names with a live sample before querying on them.** Field naming isn't
  predictable from convention or from a sibling entity's schema — a display/label field doesn't always
  follow `<name>_description` (`menu` has no description field at all), and a dependent entity's id
  field doesn't always mirror its parent's naming. Pull a live sample (`$top=1`, no `$select`) instead
  of guessing.

## Hazards once real writes start (staged add/patch/commit flow)

A staging-style write API (stage → patch → commit) has failure modes that produce **no error at all** —
the write goes through with wrong data. Never trust a clean response as proof the record is correct.

- **A multi-property write can silently drop the last property in the list.** The tools apply the list
  in sequence within one call, and setting one property can legitimately clear or reshape a later one.
  **Order the properties so a field that depends on another comes after it, and so the critical field
  is not last. Keep them in one call and re-read the response before commit.** Isolating each field
  into its own call is *not* needed — ordering alone resolves it. Known cases, all fixed by ordering:
  `control_proc_template.template_code` (after `template_description`), `list_bar_item_description` /
  `list_bar_grp_description` (after the id/target fields), `transl_object_transl.transl_plural` (after
  `transl`), `cube_view_field.cube_area` (after `order_no`), and `process_action_id` (after the
  id-deriving fields).
- **Several staged resources may be open at once, and bulk work should fan out.** Each has its own
  `staged_url`; staging 15–25 self-contained records per message (every field in the initial
  `stage_resource` `properties` call) and committing them in the next is far faster for bulk element /
  translation / menu-item work. Whatever the shape, re-read each resource's returned `fields` before
  its commit — the property-drop hazard above is per-call and per-resource, and it is most likely when
  a multi-property call reports a failed op: the property just before the failure can show as
  `applied` yet still hold its old value.
- **A commit can report the staged resource as not-found/expired** right after a successful stage/patch
  in the same sequence. Treat it as a transient hiccup: re-read the target to see whether the change
  landed; if it didn't, redo the whole stage → patch → commit from scratch rather than trying to resume
  the expired staged resource.

### Weak/dependent entities need their full key — including the parent's

A dependent entity's real key includes its parent's id: `list_bar_grp` is keyed by
`(model_id, branch_id, menu_id, list_bar_grp_id)`, and staging an edit with `list_bar_grp_id` alone
fails with `invalid_key`. A read filtered on the child id alone still returns rows, so **a read's
looser filtering is not proof the same fields make a valid edit key.** If a staged edit fails, supply
every field named in the error's `required_key_fields`/`missing_key_fields`, not just the one that
looks like "the" identifier.

### Batch `get_entity_definition` for a known object graph, but watch for token bloat

The metadata tool accepts several entity sets per call to reduce round-trips — when the object graph
is known up front (a cube needs `cube`/`cube_field`/`cube_view`/`cube_view_field`; a menu needs
`menu`/`list_bar_grp`/`list_bar_item`), request them in one batched call.

**Exception:** any entity carrying an `unlink_generated_object` bound task embeds the full
multi-hundred-value `type_of_object` enum verbatim, and batching several such entities can hit a hard
token limit. Request those one at a time — or, when the only question is the entity's own field names,
use a live sample read (`$top=1`, no `$select`) instead, which answers it far more cheaply.

### A single field's value can be truncated when read back, with no error

Reading a large text field (a control procedure template's SQL body, a generated object's code)
truncates at roughly 5000 characters with a truncation note appended. It is a per-value ceiling, not a
response-size one — changing `$select` does not move it.

**Workaround:** page through the field with an aggregation transformation:
`$apply=compute(substring(<field>, <offset>, <length>) as <alias>)&$select=<alias>`, incrementing
`<offset>` until a chunk comes back shorter than requested. **Always supply both offset and length** —
the 2-argument `substring(<field>, <offset>)` form fails with a query-execution error.

### Reuse `branch_rdbms_type`/`branch_appl_lang` already resolved this session

The same "don't re-discover what already resolved this session" caveat this skill applies to domain
keys applies to these two. Once either has been queried for the current `model_id`/`branch_id` earlier
in the task — even by a different sibling skill's step — reuse that result. They don't change
mid-task, and a multi-skill build otherwise re-fetches the same row three or four times.
