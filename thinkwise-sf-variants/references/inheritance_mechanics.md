# Variant inheritance mechanics

Loaded on demand from `thinkwise_sf_variants`.

## Inheritance — the mechanic that actually matters

Inheritance is not a documentation-only concept here — it's implemented by two genuinely different
mechanisms depending on the kind of setting, and the difference is directly visible in the model's
own entities.

### Field-level settings — always independently overridable, no snapshot

Plain scalar/flag settings on `tab_variant_overview` itself (`main_screen_type_id`,
`detail_screen_type_id`, `zoom_screen_type_id`, `popup_screen_type_id`, `icon_id`, `page_size`,
`allow_add`/`allow_update`/`allow_delete`/`allow_copy`, `max_no_of_records`,
`no_of_fields_locked`, `no_of_cols_in_form`, `badge_interval`, and similar) can each be changed on
the variant independently — changing one has no effect on any other, and every one of them
continues to silently track the default table's current value **until the variant's own value is
set to something different**. There is no explicit "activate this override" step for these.

**Only override `icon_id` (here, and on the equivalent `task_variant_overview`/
`report_variant_overview` fields below) when the variant's outcome or context genuinely differs from
the default** — per `thinkwise_sf_icons`. If a variant just prefills different
parameters for the same underlying object, leave `icon_id` tracking the default and let translation
carry the distinction instead; don't set an override as a matter of course just because the field is
there.

The same field-level pattern holds for the per-row child entities that exist automatically for
every column/task/prefilter/report/etc. once a variant is created:
`tab_variant_col_overview` gets one row per `(col_id, rdbms_type)` combination on the default table
the instant the variant is created, before any user edits anything. Verified on a live connected
model: for a table with 25 real columns, a brand-new-looking variant's `tab_variant_col_overview`
already had one row per column, and every row's `type_of_col` exactly matched its own
`default_type_of_col` — the platform-maintained mirror of the default table's current `col.type_of_col`
for that RDBMS. **`type_of_col == default_type_of_col` means the variant is still inheriting; a
divergence between them is the actual override.** Changing the default table's column type later
updates `default_type_of_col` (and, for a still-inheriting row, `type_of_col` alongside it); once a
variant sets its own `type_of_col`, the two values diverge and the variant stops tracking that
column's default type.

### Set-level settings — require an explicit "Setup" step to snapshot

A second family of child entities represents an **ordered collection** rather than one independent
value per row: grid columns, form columns, card list, tree, details, filter, search
(`combined_filter`), and sort. These are confirmed live to have a dedicated **Setup** bound task on
`tab_variant_overview` that plain field-level settings do not. This skill covers the lifecycle
mechanic (Setup/Reset/inheritance) generically across all of them; for what each field in the
grid/form/card-list/tree sets actually configures and renders, see
`thinkwise_sf_subject_components`:

| Setup task | What it snapshots |
|---|---|
| `task_setup_tab_variant_grid_overview` | Grid column set/order |
| `task_setup_tab_variant_form_overview` | Form column set/order |
| `task_setup_tab_variant_card_list_overview` | Card list layout |
| `task_setup_tab_variant_tree_overview` | Tree layout |
| `task_setup_tab_variant_detail_overview` | Detail tab set/order |
| `task_setup_tab_variant_filter_overview` | Filter field set |
| `task_setup_tab_variant_search_overview` | Search field set |
| `task_setup_tab_variant_combined_filter_overview` | Combined filter/search set |
| `task_setup_tab_variant_sort_overview` | Default sort |

**`task_setup_tab_variant_tree_overview` does not auto-populate the hierarchy link.**
Running it creates the expected `tab_variant_tree_overview` row per column, but for a self-referencing
hierarchical tree it leaves `parent_col_id` unset on all of them — the tree renders with no rows/no
hierarchy even though `tree_type`/`tree_display_col_id` are already correctly set on
`tab_variant_overview`. Fix it by explicitly setting `parent_col_id` on the **identity/PK column's**
`tab_variant_tree_overview` row to the self-referencing parent-FK column (e.g. on the `department_id`
row, set `parent_col_id = 'parent_department_id'`) — after that the tree renders correctly. Always
verify `tab_variant_tree_overview` after running the Setup task for a hierarchical tree rather than
assuming the wizard wired the hierarchy end-to-end. **Note the direction here is inverted from the base
table's own `col.parent_col_id`**, which lives on the FK column and points *at* the PK column (the
opposite row/value pairing) — see `thinkwise_sf_subject_components` for the base-table
mechanism and this asymmetry side by side.

Before Setup is called for a given set, that set has no independent identity of its own — the
variant is purely following the default's current grid/form/etc. Calling Setup takes what is
effectively a snapshot: from that point, the set stops automatically absorbing changes made to the
default. If a column is later added to the default table, an already-snapshotted grid or form on the
variant will generally **not** pick it up automatically — it stays hidden/absent until someone
deliberately adds it to the variant's own set. This is exactly the maintenance trade-off the research
literature describes: a snapshot protects a deliberately designed variant from accidental drift, but
it also means every future addition to the default has to be reviewed against every snapshotted
variant.

**Every one of the 18+ overview kinds also has a `task_reset_tab_variant_<x>_overview`** (confirmed
live for `col`, `grid`, `form`, `card_list`, `tree`, `detail`, `filter`, `search`,
`combined_filter`, `sort`, `task`, `report`, `prefilter`, `look_up`, `map`, `scheduler`, `cube`,
`conditional_layout`, and the field-level settings themselves via
`task_reset_tab_variant_overview`) — reset discards the variant's own values for that aspect and
resumes pure inheritance from the current default. Use Reset, not manual field-by-field
undo, whenever the intent is "stop this variant from diverging on X" rather than "diverge
differently."

Prefilters are explicitly **not** part of the snapshot mechanism — a `tab_variant_prefilter_overview`
row exists per prefilter automatically (same pattern as columns), and a newly added default
prefilter becomes visible to a variant without any Setup/reset step, unless the variant explicitly
overrides that prefilter's state.

### `tab_variant_change` — the live "Changes compared to default" comparator

`tab_variant_change` (bound task `task_reset_tab_variant_change` per row) is not a stored table —
it's a computed comparison: querying it for a variant returns exactly the settings
that currently differ from the default, each with `variant_col_value` and `default_col_value`
side by side (e.g. `main_screen_type_id`: variant `form_detail_no_action` vs. default `customer`;
`allow_add`: variant `False` vs. default `True`). Settings that still match the default —
verified: an unchanged `detail_screen_type_id` simply doesn't appear in the result at all. This is
the mechanism behind the platform's "Compare a variant to its default" screen, and it's the
authoritative way to audit a table variant's field-level overrides, since `tab_variant_overview`
itself carries no per-field "is this overridden" indicator the way `tab_variant_col_overview` does
with `default_type_of_col`. Query it after any bulk copy, before a release, and whenever a variant
looks like it's drifted further from its stated purpose than intended.
