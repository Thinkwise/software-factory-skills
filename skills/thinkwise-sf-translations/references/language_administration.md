# Language administration — adding and back-filling application languages

Loaded on demand from `thinkwise_sf_translations`.

## Multiple languages

**Adding a new language? Check whether it's officially supported before translating anything by
hand.** Thinkwise ships a pre-translated base model per officially supported GUI language
(`GUI_TRANSL_<lang>`, plus a narrower `<RDBMS>_MSG_TRANSL_<lang>` for database error text on some
RDBMS/language combos) — linking and merging that base model back-fills the platform's own standard
translations for free. Manual translation via this skill is then only needed for the application's
**own** objects. See `references/officially_supported_languages.md` for the live-verified language
↔ base-model mapping and the full link → merge → generate recipe before doing any manual work on a
newly-added `branch_appl_lang`.

**`appl_lang`** (in a `manage_datamodel`-style domain, model-independent) is the global catalogue:
`appl_lang_id` (the IETF tag, e.g. `en-US`, key) and `appl_lang_description`. **`branch_appl_lang`**
(in `manage_translation`) links one of those to a specific `(model_id, branch_id)` — it's how a branch
declares which languages it actually supports; keyed by `(model_id, branch_id, appl_lang_id)`, no
translatable fields of its own beyond `generated_by_control_proc_id`. Query `branch_appl_lang` first
to know how many languages a `help_text` decision (above) or a plural-review pass (above) actually
needs to cover — don't assume the shipped six (`nl-NL`/`en-US`/`de-DE`/`fr-FR`/`es-ES`/`pt-PT`); the
live `INSIGHTS` example has eight, including `it-IT`, `ja-JP`, and `pt-BR` instead of `pt-PT`.

**Cleaning up orphaned translation objects.** `branch_appl_lang` carries a zero-parameter bound task,
`task_delete_unused_transl_objects` ("Delete unused translation objects — Delete unused translation
objects for the entire branch"): it deletes every `transl_object`/`transl_object_transl`
row whose underlying model object no longer exists, branch-wide, in one call. The most common source of
these orphans is renaming something — a rename task changes an object's id but doesn't clean up the
*old* id's translation rows, which then sit around indefinitely holding stale bracket-placeholder text
under an id nothing points to anymore. Reach for this task after any rename, or as a periodic branch-wide
sweep, rather than hunting down a specific orphaned row by hand once you happen to notice one. **This
task can be entirely invisible without the right Software Factory role/rights on the connected
account**: `branch_appl_lang`'s bound-task list came back empty and a direct lookup by
this task's exact name returned a hard "not found," indistinguishable from the task simply not
existing, until the account's rights were adjusted — see `thinkwise_sf_data_model`'s
role/rights quirk for the general version of this trap.

**Generating translation objects.** New objects normally get a `transl_object` automatically on
creation on `tab`'s own `task_create_tab_variant`, which carries a
`generate_transl_object: Edm.Boolean` parameter controlling exactly this. For anything created without
going through such a task (most commonly dynamic-model objects), call the relevant
`task_generate_transl_objects` variant afterward — it exists both as a generic bound task on
`transl_object`/`transl_object_transl` and as dozens of narrower unbound variants scoped to a specific
parent (`generate_transl_objects_help_index_help_index_id`,
`generate_transl_objects_tab_check_constraint_check_constraint_id`,
`generate_transl_objects_module_grp_module_grp_id`, and many more) — use
`search_domain_capabilities` in `sf/manage_translation` to find the variant matching the parent object
type actually in play rather than assuming the generic one always applies.

**Confirm the row is actually missing before reaching for this recipe.** Whether a dependent-record-added
`list_bar_grp`/`list_bar_item` gets an auto-generated `transl_object` for free is inconsistent across
sessions — one session found zero rows immediately after creating and committing the group/item (the
case this recipe was built for), another found a real bracket-placeholder already there with no extra
steps, for the same kind of object created the same way. Run the bare-id query from step 3 at the top
of this skill first; only fall through to hand-backfilling below if that query genuinely comes back
empty.

**Backfilling a missing `transl_object` by hand — the working recipe for a
`list_bar_item` (a case earlier assumed to be a dead end):**

1. **Add the `transl_object` row directly** (`model_id`, `branch_id`, `type_of_object`,
   `transl_object_id` matching the target object's own id) — this succeeds as a plain add, no bound
   task needed.
2. **Run the *generic* `task_generate_transl_objects`, bound to that exact `transl_object` row you
   just created** (zero params). This is the key step that's easy to skip: it's not the narrow
   per-parent-type unbound variant (`generate_transl_objects_<parent>_<parent>_id`-shaped) — that
   narrow variant can fail on its own hidden mandatory `branch_id` with no exposed way to target one
   record. The generic bound task on `transl_object` succeeded where the narrow variant didn't, and
   produced the bracket-placeholder `transl_object_transl` row for every configured language.
3. **Edit that `transl_object_transl` row normally** (it's now an existing row addressed by its full
   key including `appl_lang_id`, not a fresh add) — the fields patch and commit like any other
   translation.

**Why hand-adding `transl_object_transl` directly (skipping step 2) fails**: on a brand-new add,
`appl_lang_id` shows as hidden-yet-mandatory and rejects any attempt to patch it — a real, confirmed
dead end for that specific path. The fix isn't to abandon the API and go to the Software Factory's own
UI, it's to route through step 2's generate task instead of trying to hand-craft the child row.

If a future case still has no working path after trying all three steps above, *then* treat manual
translation directly in the Software Factory as the practical fallback — but confirm that by actually
attempting this recipe first, since it resolved what previously looked unrecoverable.

**Review workflow.** `approval_status` starts `not_yet_approved` on a new/changed translation.
`task_mark_transl_object_transl_approved` (zero params) approves it; disapproving requires
`task_mark_transl_object_transl_disapproved` with a mandatory `feedback` string — there is no way to
disapprove without leaving a reason. Treat `approval_status` as the gate for whether a set of
translations is safe to consider final, especially before a merge — an edited, previously-approved
translation resets to `not_yet_approved` (per platform docs; not independently re-verified live in
this session), so a stale "approved" count is a real risk signal, not just paperwork.

**Fallback language.** Referenced in platform documentation (used when a user's own language has no
translations in a given application) but its storage location was **not** found during live
verification in either `sf/manage_translation` or `sf/manage_datamodel` — it did not surface as a
field on `branch`, `appl_lang`, or `branch_appl_lang`, and no `sf_configuration`-style entity was
reachable from either domain in this session. Confirm its actual entity/field (or that it's a setting
only exposed in the Software Factory's own UI, with no exposed API surface) live before scripting
anything that depends on it, rather than assuming a name from documentation alone.

**Parameterized labels.** Per platform docs, `transl_form` (and the group/section label fields
surfaced via `col`/`report_parmtr`/`task_parmtr`'s `form_next_grp_label`/`grid_next_grp_label`
lookups above — see `thinkwise_sf_subject_components` for what those group/section
fields actually do on a Form or Grid) can carry `{placeholder}` tokens resolved with locale-aware
date/number formatting.
Not recursive, resolved exactly once, and an undefined/null parameter is silently dropped rather than
breaking the string — not independently re-verified live in this session, treat as documented
behavior to confirm if a parameterized label misbehaves.
