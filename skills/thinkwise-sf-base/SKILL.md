---
name: thinkwise-sf-base
description: Base check to run before doing real work through any MCP connector that provides Thinkwise Software Factory access. Confirms which connector (and its profile — Indicium MCP split- or single-domain, legacy sf-mcp-server, or none — plus the surface, Claude Code or claude.ai/ThinkIT), which application model, and which branch (model_id/branch_id) apply, since one Software Factory repository commonly hosts several application models with multiple branches each and most entities are keyed by model_id/branch_id. Use once near the start of a task, not before every individual tool call.
---

# Software Factory MCP base check

Three things have to be pinned down before real Software Factory work starts: **which connector**,
**which application model**, and **which branch**. All three are easy to get wrong silently — a
query with no explicit `model_id`/`branch_id` filter can match rows from an entirely different
model or branch in the same shared repository (see `thinkwise-sf-data-model`). Run this
check once per task, before the first substantive read/write call, not on every tool call.

## Terminology — never call it "Studio"

The Thinkwise design-time modeling tool — where a developer edits tables, tasks, maps and control
procedures outside any MCP connector — is **the Software Factory**. **Never call it "Studio"**; that
name appears in no Thinkwise documentation or terminology. When a manual step is needed outside what a
connector can reach, say "the Software Factory" (or "the Software Factory's GUI Modeler" for a specific
screen).

## 1. Which connector — and which profile, layout and surface

Look at the connected MCP servers that expose the Software Factory toolset (tool names like
`get_domain_definition`, `execute_odata_query`, `stage_resource`, or `create_entity`/`query_entities`).
Other Thinkwise applications behind Indicium expose the same tool names: count an Indicium connector only
when its server instructions name an `sf/…` domain (e.g. `sf/software_development`, `sf/manage_tasks`).

- **Exactly one such connector connected** → use it, don't ask.
- **More than one**, and the user's request doesn't already name one → ask the user which one, listing
  the connector names as options.
- If the user's message already names or implies the connector, use that — don't ask again.

Then pin down the environment, using `references/connector_profiles.md`:

- **Connector profile** — Indicium MCP (staging tools), legacy sf-mcp-server (`create_entity`/
  `query_entities`), or no connector at all.
- **Domain layout** (Indicium only) — split (`sf/manage_*`) or single (`sf/software_development`); read
  it from the connector's server instructions (they name the domain keys), else `search_capabilities`.
  Don't call `get_available_domains` for it — the answer can run to hundreds of thousands of characters.
- **Surface** — Claude Code (`AskUserQuestion`) or claude.ai/ThinkIT (`ask_user_input_v0`).

Rules in the sf-* skills tagged `(Indicium · split-domain)`, `(legacy sf-mcp-server)`, `(older
meta-model)` etc. apply only there; untagged rules apply everywhere. Everything below about staging,
`detail_nav` and bound tasks is **Indicium MCP** behaviour. With the legacy connector or without one, the
entity/field knowledge in the sf-* skills still holds, but the write routes don't — see the carry-over
table in `references/connector_profiles.md`.

**Asking the user**, wherever any sf-* skill says so: the surface's structured question tool
(`AskUserQuestion` in Claude Code, `ask_user_input_v0` in claude.ai/ThinkIT), otherwise a short
numbered question in text.

## 2. Which application model

A repository can hold multiple application models (e.g. `RK_MERIDIAN`, `RK_SCHEDULER_TEST`,
`INSIGHTS`), each scoped by its own `model_id`. Only ask about this when the task actually touches
model-specific data (tables, tasks, screens, control procedures, process flows, etc.) — pure
metadata/discovery calls like `search_capabilities` don't need it yet.

- If the user's message, or anything earlier in this conversation, already names the application
  model (or it's unambiguous from context, e.g. only one model exists in the repository) → use
  that, don't ask.
- Otherwise, list the distinct `model_id` values available through the chosen connector (e.g. a
  grouped query on `branch`, with description) and ask the user to pick one. Skip
  the ask if that query turns up only one model.

## 3. Which branch

Once the application model is settled, the same repository query also carries `branch_id` —
each model typically has more than one branch (e.g. a mainline plus feature/test branches).

- If the user's message, or anything earlier in this conversation, already names the branch (or
  only one branch exists for the chosen model) → use that, don't ask.
- Otherwise, list all branches for the chosen `model_id` (e.g. filter that same `branch` query by
  `model_id`) and ask the user to pick one, showing every branch found.

## Once resolved

Treat the chosen connector (with its profile, domain layout and surface), `model_id`, and `branch_id`
as pinned for the rest of the task — carry
them into every subsequent `execute_odata_query`/`stage_resource`/`stage_task` filter and
parameter, and don't re-ask unless the user switches context to a different model, branch, or
connector.

## Shared conventions every other Software Factory skill builds on

Every `thinkwise-sf-*` skill inherits these rules **instead of restating them**. Where a
skill's own text conflicts with these, follow these.

- **Confirm-before-mutate.** Before the *first* `stage_resource`/`stage_task`/`patch_resource`/
  `commit_resource` call for a piece of work, state the concrete plan in plain language — what will be
  created/changed, the key design choices, and how it fits the existing model — and get explicit
  confirmation. Scope the plan to the work's real grain: a multi-artifact goal gets one bundled plan
  (`thinkwise-sf-build-planner`); a single artifact gets a short plan covering its own
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
- **A field missing from a query row is null.** `execute_odata_query` leaves null fields out of each
  returned row; treat a missing field as null, not as an unknown field or a failed `$select`.
- **Edit an SF-generated overview row only when the edit really changes it.** Some rows exist per
  combination of objects (e.g. `tab_variant_prefilter_overview`, the `role_*_overview` rights rows) and
  stay virtual until a change is stored. An edit that sends the row's current value either fails
  (`mandatory_empty: delegated_update`, or `gui_cannotsavemandatory` on commit) or commits as a silent
  no-op — read the rows first and edit only those whose value differs.

## Hazards once real writes start (staged add/patch/commit flow)

This section and the ones under it are **Indicium MCP** behaviour (see §1).

A staging-style write API (stage → patch → commit) has failure modes that are easy to miss — a refusal
arrives looking like a normal result, or the write goes through with wrong or missing data. Never trust
a clean-looking response as proof the record is correct.

- **A refusal is a normal result, not a tool error.** Every write tool — `commit_resource` included —
  reports a refusal as an ordinary result `{error, status, detail}` without the tool-error flag (seen:
  `422 gui_cannotsavemandatory` on a commit with an empty mandatory field). **Treat any numeric
  `status` in a response as a failure.** Don't retry a `401` (repeated bad credentials risk a
  lock-out); a `403` is a missing right or an unoffered route, so retrying unchanged achieves nothing.
- **After any error, read back before retrying — the operation may have partly succeeded.** Seen:
  `task_create_model` answered `422 branch_is_read_only` on commit, yet the model and its branch
  *were* created. A re-run would have collided with what already existed.
- **A multi-property write applies its properties in order and stops at the first refused one.** The
  refused property comes back as `failed_operation` (typically `field_not_editable` or `no_field_view`
  — the field is hidden or read-only for the record as it stands), and every property after it lands
  in `not_applied`. This is what earlier looked like "the last property silently drops": when the
  refused property happens to be last, only the last one is lost. A type or discriminator field can
  also clear or re-derive the fields after it. **Order the properties: key fields first, then each
  enabling field before the fields it opens (`dttp_id` before `length`, `control_id` before
  `file_storage_id`, a `*_type` field before its target), and code/long-text fields last. Keep them
  in one call, read the response's `error`/`not_applied`, and re-read every written field before
  commit.** Don't commit a half-applied record — it hides the real cause. Isolating each field into
  its own call is *not* needed — ordering alone resolves it. Known cases, all fixed by ordering:
  `control_proc_template.template_code` (after `template_description`), `list_bar_item_description` /
  `list_bar_grp_description` (after the id/target fields), `transl_object_transl.transl_plural` (after
  `transl`), `cube_view_field.cube_area` (after `order_no`), and `process_action_id` (after the
  id-deriving fields).
- **Look-up/key fields resolve by display value by default.** A plain value is matched against the
  look-up's display column, which need not equal the key: a branch can display as
  `MAIN (read-only)`, so `branch_id = 'MAIN'` failed with `lookup_not_found`. For key look-ups pass
  `value_kind: "data"` with the raw key (or numeric enum value).
- **Enum-valued fields come in two shapes — check which before sending.** Most are numeric: send the
  number, not the name (`summary_type: "sum"` is refused; send `6`). Others are string-element domains
  whose stored value is the element id (e.g. `assignment_method = 'variable'`, not a number). When a
  value is refused with `validation_data_domain_element`, read an existing row's stored value for that
  field to learn the element ids, then send one of those (verified through the write API on SF 2026.2).
- **A fresh model's branch refuses connector writes until a person allows it.** A newly created
  model's branch has `allow_delegated_mutation = false` (and `protected = true`), and every connector
  write to it fails with `branch_is_read_only`. The connector cannot flip that flag itself — ask the
  user to enable delegated mutation on the branch in the Software Factory. (On an existing branch the
  same error can also be a rights gap — see `thinkwise-sf-translations`'s officially-supported-languages
  reference.)
- **A locked branch refuses writes.** While `branch.lock_status` is not 0 (1 copy, 2 delete, 3 merge,
  4 code generation, 5 base model copy), writes fail with `422 error_branch_lock_<held>_<asked>` —
  also for the user whose own job holds the lock. `task_generate_code_grp` holds lock 4 for roughly
  0.3–2.3 s per run, so run one code-group generation per branch at a time and retry a lock error with
  backoff. Use the branch's Reset lock task only for a lock a crashed job left behind, never for one a
  running job holds. (Reported on SF 2026.2.)
- **Several staged resources may be open at once, and bulk work should fan out.** Each has its own
  `staged_url`; staging 15–25 self-contained records per message (every field in the initial
  `stage_resource` `properties` call) and committing them in the next is far faster for bulk element /
  translation / menu-item work. Whatever the shape, re-read each resource's returned `fields` before
  its commit — the property-drop hazard above is per-call and per-resource, and it is most likely when
  a multi-property call reports a failed op: the property just before the failure can show as
  `applied` yet still hold its old value. Separate connector sessions are independent of each other,
  so parallelizing across sessions is safe.
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

To **add** a dependent record, stage it under its parent (`parent_entity_set` + `parent_key`). When the
parent has more than one detail navigation to the child, also pass `detail_nav`, or the add fails with
`ambiguous_detail_nav` (e.g. `process_flow` under `branch`: `detail_ref_branch_process_flow`, or
`detail_ref_branch_process_flow_sub_flow` for a sub-flow). Some children can only be **added** through
a variant entity set — on the plain set the add is refused or answers `detail_nav_not_found` — while
edits and deletes use the plain set. Some of these routes depend on the domain layout:

| Child (parent) | Add through | Layout |
|---|---|---|
| `process_variable` (`process_flow`) | `process_variable.process_variable_modeler` under the parent | single-domain; split-domain also accepts a flat add |
| `tile` (`tile_grp`) | split: `tile.gui_modeler_tile` under the parent · single: **flat** add with the full key (under-parent answers `detail_nav_not_found`) | differs |
| `cube_field` (`cube`) | `cube_field.gui_modeler_cube_field_type_dimension` / `..._type_value` under the parent | both |
| `unit_test_col_filter` (`unit_test`) | `unit_test_col_filter.trigger` under the parent | both |
| `web_connection_endpoint_parmtr` (`web_connection_endpoint`) | split: `web_connection_endpoint_parmtr.gui_modeler_web_connection_endpoint_parmtr` under the parent · single: **flat** add with the full key | differs |
| `web_connection_endpoint_output_parmtr` (`web_connection_endpoint`) | single: **flat** add with the full key · split: not verified, try under the parent | differs |
| `task`, `msg`, `menu` (`branch`) | under `branch` — a bare add is refused | single-domain; split not verified |

Some children aren't added at all: the Software Factory pre-lists one candidate row per parent element
in an `_overview` set (`allow_add = false`, `allow_update = true`), and editing the candidate creates the
real row — e.g. `map_data_mapping_overview`, `scheduler_view_resource_col_overview`.

If the listed route is refused, try the other one before treating it as unsupported.

### Batch `get_entity_definition` for a known object graph, but watch for token bloat

The metadata tool accepts several entity sets per call to reduce round-trips — when the object graph
is known up front (a cube needs `cube`/`cube_field`/`cube_view`/`cube_view_field`; a menu needs
`menu`/`list_bar_grp`/`list_bar_item`), request them in one batched call.

**Exception:** any entity carrying an `unlink_generated_object` bound task embeds the full
multi-hundred-value `type_of_object` enum verbatim, and batching several such entities can hit a hard
token limit. The same goes for entities and tasks with many variants or large enums
(`template_prog_object_item`, `unit_test_col_filter`, the translation approval task — one answer ran to
~78 KB). Request those one at a time — or, when the only question is the entity's own field names,
use a live sample read (`$top=1`, no `$select`) instead, which answers it far more cheaply.

### A single field's value can be truncated when read back, with no error

Reading a large text field (a control procedure template's SQL body, a generated object's code)
truncates at roughly 5000 characters with a truncation note appended. It is a per-value ceiling, not a
response-size one — changing `$select` does not move it.

**No reliable chunked-read workaround.** Paging with
`$apply=compute(substring(<field>, <offset>, <length>) as <alias>)` has been tried and was silently
ignored — the plain truncated field came back with no alias field (see
`thinkwise-sf-postgresql-migration`'s `references/known_issues_and_gaps.md`); the 2-argument
`substring(<field>, <offset>)` form failed outright. Also reported on SF 2026.2, not re-verified:
`$compute` refused, `$filter` with `length()` capped at 500, and a suggestion to keep each template under
~4500 characters (or split the logic over several templates of one control procedure, `order_no` 10,
20, …) so a plain read-back still shows it whole. If a field is too long to read completely, say so and
hand the full comparison off to the Software Factory UI rather than reconstructing it.

**Compare after normalising.** A read-back can differ from what was sent without anything being wrong:
trailing whitespace is trimmed and CRLF line endings normalised in code fields; an override equal to
the inherited value is stored empty (e.g. `form_type_of_col` equal to `type_of_col` reads back empty);
an enum sent as its display value reads back as its data value. Normalise for these before deciding a
write failed.

### Reuse `branch_rdbms_type`/`branch_appl_lang` already resolved this session

The same "don't re-discover what already resolved this session" caveat this skill applies to domain
keys applies to these two. Once either has been queried for the current `model_id`/`branch_id` earlier
in the task — even by a different sibling skill's step — reuse that result. They don't change
mid-task, and a multi-skill build otherwise re-fetches the same row three or four times.

### Routes known not to work through the write API

Observed on SF 2026.2 — plan these as a manual step in the Software Factory: starting a merge (it needs
an existing `merge_session`, and a `merge_session` cannot be added) and renaming a branch. Refusals tied
to one object type live in that object's skill — e.g. `prog_object` adds
(`thinkwise-sf-control-procedures`), diagrams (`thinkwise-sf-data-model`), complete creation
(`thinkwise-sf-deployment`), report layout upload (`thinkwise-sf-reports`). Before recording any new
"doesn't work" route, rule out a rights gap first (see `thinkwise-sf-data-model`'s
`references/api_write_quirks.md`).
