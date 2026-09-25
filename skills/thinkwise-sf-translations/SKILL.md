---
name: thinkwise-sf-translations
description: Reference guide for translating model objects in a Thinkwise Software Factory model — the transl_object entity family, the approval_status review workflow, naming/plural/help-text conventions, and linking a base model to back-fill an officially supported language instead of hand-translating it. Use whenever an MCP connector with Software Factory access reads, writes, generates, or reviews translations, or adds a new application language.
---

# Translating Objects in the Thinkwise Software Factory

Every translatable thing in a model — a table, a column, a domain element, a task, a report
parameter, a menu, a validation message, and roughly 150 other concepts — gets exactly one
`transl_object` row, keyed by `(model_id, branch_id, type_of_object, transl_object_id)`. Each
`transl_object` then has one `transl_object_transl` child row **per configured application
language**, keyed by the same four fields plus `appl_lang_id`, holding the actual translated text.
Everything in this skill was confirmed live against a real connected model (`INSIGHTS`, branch
`MAIN`) via `sf_mcp`.

Apply this whenever an MCP connector with Software Factory access is used to read, write, generate,
or review translations. `transl_object`, `transl_object_transl`, and `branch_appl_lang` live in a
`manage_translation`-style domain (confirmed `sf/manage_translation` live); the master `appl_lang`
list (the global catalogue of IETF language tags, independent of any model) lives in a
`manage_datamodel`-style domain instead ## Golden rule — several moves here need the user's word, not the assistant's judgment

The mechanics of reading and writing translation rows are simple API calls. A handful of moments in
that flow are design or process decisions that belong to the user, not something to resolve
silently by picking whatever seems safest — the `thinkwise_sf_base`
"Confirm-before-mutate" convention applied at this skill's own grain:

- **Hand-creating a `transl_object`.** The platform generates these automatically in almost every
  case; hand-inserting one is a last resort and requires confirming with the user first — the object,
  the `type_of_object` you intend to use, and why the automatic paths didn't apply (see "Before
  anything else" below).
- **Deciding `help_text` coverage scope.** Filling in `help_text` for one language is an implicit
  promise to cover every configured `branch_appl_lang` or knowingly leave the rest without it — ask
  the user which before writing any `help_text` (see "Help text" below).
- **Disapproving a translation.** `task_mark_transl_object_transl_disapproved` has a mandatory
  `feedback` string — there is no way to disapprove without a reason, so that reason has to come from
  the user (or genuinely reflect their stated concern), not be invented to satisfy the parameter.

Only skip asking when the user has already stated the answer unambiguously.

## Before anything else: find the existing object — don't create one

Nearly every translatable object already has an auto-generated `transl_object` row the moment
it's created in the model — even if nobody has ever translated it, that row exists, holding
`[bracketed]`-placeholder text (see "Detecting untranslated objects" below). **If you've been
asked to translate something, a row for it almost certainly already exists.** The job is almost
always to find that row and overwrite its placeholder `transl_object_transl` text — not to add a
new `transl_object`. The platform generates translation objects; you very rarely should.

Mandatory sequence, in order:

1. **Identify the object's kind and id** (a table, a column, a menu item, a role, …).
2. **Look up the candidate `type_of_object` value(s)** in the lookup table below. If that kind is
   flagged as having a trap (its real translation lives under a *different* `type_of_object` than
   its own name suggests), check the trap target **first**, not the literal name.
3. **Query `transl_object` filtered to just the bare `transl_object_id`** (no `type_of_object`
   filter) to see every type it's actually registered under, and cross-check the results against
   the lookup table — don't trust the first hit or assume "no row at the obvious type" means "no
   row anywhere."
4. **If a row exists, that's the one to edit.** Fetch its `transl_object_transl` for the target
   language(s). If the field(s) show the `[bracketed]` placeholder, overwrite that text — that's
   the actual translation work. If it already holds real, non-bracketed text, it's already
   translated; leave it alone unless explicitly asked to change existing text.
5. **Only if step 3 finds nothing at all**, across every plausible type for that kind, is the row
   genuinely missing. Reach for the platform's own generation path first — the object's own
   `generate_transl_object`-style creation parameter, or the matching `task_generate_transl_objects`
   variant (see "Generating translation objects" below). That's still the platform creating the
   row, not you hand-authoring one.
6. **Hand-inserting a `transl_object` row directly is the last resort**, and requires confirming
   with the user first: name the object, the `type_of_object` you intend to use, and why the
   automatic paths in step 5 didn't apply. Never create one silently — see "Backfilling a missing
   `transl_object` by hand" below for the mechanics once confirmed.

**About to add a new `transl_object`? Stop.** Re-run the bare-id search from step 3 across the
lookup table's candidates first. In the overwhelming majority of cases the row already exists —
either under a `type_of_object` you weren't expecting, or holding placeholder text that was
mistaken for "missing."

## Bulk-importing translations in one call — check for a custom task first

Some models have a rare, custom-built task that upserts a whole batch of translations in one JSON
call instead of writing each row individually. For the full workflow, JSON payload shape, and its
verified gotchas, read `references/bulk_import.md` before assuming this path is or isn't available
in the model you're working with.

## The two core entities

### `transl_object` — one row per translatable object

| Field | Type | Notes |
|---|---|---|
| `model_id`, `branch_id` | key | |
| `type_of_object` | key, `Edm.Int32` enum | Which kind of model concept this is — see below. |
| `transl_object_id` | key, string | The object's own ID (a column's `col_id`, a table's `tab_id`, a domain element's `elemnt_id`, …). **Not qualified by owner** — see the naming gotcha below. |
| `transl_object_description` | string | Free-text description of the translation object itself (not a translation). |
| `insert_user`/`insert_date_time`/`update_user`/`update_date_time` | trace | |
| `generated_by_control_proc_id` | string | Set when the object/its translations were produced by a control procedure rather than authored directly. |

Bound tasks: `task_generate_transl_objects` (zero params — backfills a missing `transl_object` for
an object that already exists in the model but has none yet, e.g. something created outside the
normal flow via a dynamic model), `task_show_history`, `task_unlink_generated_object`.

`transl_object` carries roughly ninety `detail_ref_transl_object_<parent>` navigation properties (to
`col`, `tab`, `dom_elemnt`/`elemnt`, `task`, `report`, `menu`, `cube_view`, `screen_type`,
`conditional_layout`, `role`, and many more) — this is how a `transl_object` row is actually reached
from its owning model object; don't try to derive `transl_object_id` from the parent's key structure
by convention, confirm it via the correct navigation property or by reading `transl_object_id`
directly off a query result.

### `transl_object_transl` — one row per object per language

| Field | Type | Shown where (per platform docs, cross-checked live) |
|---|---|---|
| `model_id`, `branch_id`, `type_of_object`, `transl_object_id` | key | Same as parent `transl_object`. |
| `appl_lang_id` | key, string | IETF tag, e.g. `en-US`, `nl-NL`. |
| `transl` | string | General-purpose single label; the fallback used wherever no more specific field is set. |
| `transl_form` | string | Form labels, formlists, task/report parameter pop-ups. |
| `transl_grid` | string | Grid column headers. |
| `transl_card_list` | string | Card list headers (undocumented in the platform docs pulled for this skill, but a real, distinct field — confirm intent with the user before assuming it always mirrors `transl`). For what `card_list_label`/`card_list_order_no`/etc. actually control on the card itself, see `thinkwise_sf_subject_components`. |
| `transl_plural` | string | List/detail tab headers, card list headers — see Plural forms below. |
| `tooltip_text` | string | Hover hint; basic HTML allowed. |
| `help_text` | string | Longer-form, feeds Help screens — see Help text below. |
| `approval_status` | `Edm.Byte` enum: `not_yet_approved`=0, `approved`=1, `disapproved`=2 | Per-language, per-object review state. |
| `feedback` | string | Reviewer's note when disapproving. |
| `insert_user`/`insert_date_time`/`update_user`/`update_date_time` | trace | |
| `generated_by_control_proc_id` | string | |

**Which text fields are actually live depends on `type_of_object`.** The API marks each of
`transl`/`transl_form`/`transl_grid`/`transl_card_list`/`transl_plural` as editable-and-mandatory or
hidden per record, and this varies by the owning object's `type_of_object` rather than being fixed —
confirmed live: a `tab` (0) row carries `transl`+`transl_plural`; a `col` (1) row carries
`transl`+`transl_form`+`transl_grid`+`transl_card_list` (no `transl_plural`); a `task_parmtr` (32) row
carries only `transl`+`transl_form`; most other types (`dom_elemnt`, `task`, `list_bar`, `menu`,
`scheduler_view`, …) carry `transl` alone. Fetch the record first and set only the fields it reports
as editable/mandatory — writing a fixed set of "all five fields" on every object either fails on
fields the object doesn't have, or silently sets fields the UI never shows.

Bound tasks (all zero-parameter except the one noted): `task_enrichment_auto_transl` ("translate with
AI" for this one row — drafts from an already-translated language), `task_generate_transl_objects`,
`task_mark_transl_object_transl_approved`, `task_mark_transl_object_transl_disapproved` (**mandatory
`feedback` string parameter** — cannot disapprove without a reason), `task_show_history`,
`task_transl_selected_objects` ("translate by ID" — derives a label from the object ID: underscores
to spaces, first letter capitalized), `task_unlink_generated_object`.

— table `activity` in model `INSIGHTS`, branch `MAIN` — surfaced three points made
elsewhere in this skill at once:

- **Eight configured languages**, not the shipped six — including a regional variant (`pt-BR`, not
  plain `pt`) and a non-Latin script (`ja-JP`).
- `transl_plural` authored independently per language, not derived from `transl` (see Plural forms
  below).
- `help_text` filled for only 2 of the 8 languages (`en-US`, `nl-NL`) — see Help text below.

## Detecting untranslated objects — look for the bracketed placeholder, not a blank field

A newly generated `transl_object_transl` row is not blank. The platform auto-fills every mandatory
text field with the object's own ID wrapped in square brackets — `[activity]`, `[employee_id]`,
`[employee_schedule_add_activity]` — as a fallback label, and that bracketed placeholder is what
still shows in the Software Factory's own UI for text nobody has actually translated. Confirmed live: querying
`transl_object_transl` for one language in a small custom model returned zero rows with `transl`
null or empty, but fifty-five rows across `transl`/`transl_form`/`transl_grid`/`transl_card_list`/
`transl_plural` matching `startswith(field,'[') and endswith(field,']')`. That bracket test is the
real "still needs translating" query — a null/empty check alone will under-report almost everything.

**Exception, also confirmed live:** a `gui_object` (`type_of_object = 13`) with `transl` set to a
single literal space (not empty, not bracketed) was not a missed translation — it was an
intentionally blank label on a layout/spacer control, where a real caption would introduce an
unwanted header in the UI. Before "fixing" any blank-looking (not bracketed) translation, check
whether the owning object is this kind of spacer/filler control rather than assuming it's simply
untranslated.

## `type_of_object` — one enum, ~150 values, spanning almost the whole model

`type_of_object` is not specific to tables/columns/domain elements — it is the same enum used to key
*every* translatable concept in the platform, and it grows across platform versions. **Always fetch
the current values live** — `get_entity_definition` (or the connector's equivalent metadata call)
against `transl_object`/`transl_object_transl`'s `type_of_object` property/domain — rather than
trusting any hardcoded list, including the one in the reference file below.

For the full `type_of_object` value table and its known traps (`tab_label`, `list_bar_grp`,
`cube_field`, rename-orphan, and more), read `references/type_of_object_lookup.md` before writing a
`type_of_object` filter or interpreting a lookup result.

## Naming and text conventions

**The object id *is* the translation key** — renaming an object orphans its translation rows, so
translate after the id is settled, and sweep for orphans after any rename.

Two text rules: **avoid the literal word "ID" in translated text** (users read it as jargon — use the
business term), and leave `approval_status`/help text empty by default rather than inventing filler.

For the naming conventions in full, per-language plural forms (authored, never derived), and the
help-text review workflow, read `references/naming_and_text.md`.

## Multiple languages

A branch's configured languages live in `branch_appl_lang`; every `transl_object` needs one
`transl_object_transl` row **per configured language**, so adding a language multiplies the rows that
need text.

**Don't hand-translate an officially supported GUI language.** Thinkwise ships pre-translated base
models that can be linked and merged to back-fill the platform's own standard translations, leaving
only the application's *own* objects to translate. Do not infer the base model's name from a
`model_id` suffix — that is a hint, not a contract; look it up.

For adding a language end to end (linking and merging a base model, `linked_model` /
`linked_model_available`, the `task_generate_transl_objects` variants, the `branch_appl_lang` cleanup
task, and sweeping for orphaned translation objects), read `references/language_administration.md`.

## Pre-flight checklist

- **Adding a new language that's on the officially supported list?** Link its `GUI_TRANSL_<lang>`
  base model (and matching `<RDBMS>_MSG_TRANSL_<lang>` if one exists for the branch's RDBMS), merge
  it into the work model, and generate — before doing any manual translation. See
  `references/officially_supported_languages.md`.
- **`transl_object_id` for a column is the bare column ID, not qualified by its table** — before
  editing a column's translation, check whether other tables reuse the same `col_id` (query `col`
  filtered on that `col_id` across the model) and confirm the edit is meant to apply everywhere it's
  used, or rename/point `alt_transl_col_id` elsewhere first.
- **Check for `alt_transl_*`/`*_next_grp_label`/`*_next_tab_label`/`*_confirm_button`/
  `*_cancel_button` on the parent object** before concluding an object has only one translation — many
  do not.
- **`form_next_grp_label`/`next_tab_label` resolve against `type_of_object = tab_label` (33), not
  whatever type the owning object is**. Don't translate the owning column/parameter's
  own `type_of_object` row and assume that's the group/tab-section label; verify which `type_of_object`
  actually holds a `[bracketed]` placeholder for that literal label text before writing to it. Committing
  to the wrong type_of_object succeeds with no error and leaves the real UI-visible label untranslated.
- **A `list_bar_grp`'s real translation is `type_of_object = list_bar` (12), not `list_bar_grp` (78)**, the same shape of mismatch as `tab_label` above. Query all `type_of_object` values
  for the bare group id and cross-check `insert_date_time` against the group's own creation to find the
  real, auto-generated row before translating. `list_bar_item` (79) has no navigation property on
  `transl_object` at all and no known working consumer — a table/report-linked menu item just shows
  the linked object's own translation.
- **`tile_grp`/`module_grp`/`tab_task` do *not* share the `list_bar_grp` trap**.
  `tile_grp` (87) and `module_grp` (6) group headers translate under their own type directly, no
  redirect. `tile` (84) has the same "no working path" shape as `list_bar_item`. `tab_task` (110)
  has no `transl_object` navigation property at all — a table-bound task's label is the parent
  `task`'s (11) own translation, not a `tab_task`-scoped row.
- **A `cube_field`'s label (25) is independent of its `col_id` column's own translation (1)** —
  translating one does nothing for the other, and multiple `cube_field` rows sharing one `col_id`
  each need their own translation. `cube_view` is `type_of_object = 26`.
- **A rename task cascades functional references but not translations** — after renaming a
  translatable object through its dedicated rename task, check for and delete the old id's orphaned
  `transl_object`/`transl_object_transl` rows rather than assuming the rename handled them.

