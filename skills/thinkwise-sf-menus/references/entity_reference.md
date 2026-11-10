# Menu entity and task reference — creating menus, groups, items and role rights

Loaded on demand from `thinkwise-sf-menus`.

## Creating things: verified entity/task reference

### Menu

No bound "create" task exists for `menu` — create it as a plain new record (the generic
connector's insert/`add` flow) with `menu_id` and `menu_type` only — confirm `menu_type` up front: it was editable on an edit of a
menu without groups (verified on SF 2026.2), but is reported to lock once the menu has groups — then `show_filter`/
`show_open_documents`, and `icon_id` (a suitable icon per `thinkwise-sf-icons` — broad
and stable, representing the whole application/module the menu covers, not one frequently-used screen)
as wanted. `menu_platform` comes back `readonly` at create with a default that differs by model and
version (`8` = `universal` in one model, `1` in another) — read it back rather than assume a value; you
may not be able to set it in the create call, and universal is the only actively-maintained target anyway (see "New menu, or the existing one?"
above), so don't treat a readonly `menu_platform` as an error. Staging the `menu` as a dependent
record of `branch` (`parent_entity_set: "branch"`, `parent_key: {model_id, branch_id}`) works if a
bare add is rejected. `task_rename_menu` (params `branch_id`, `from_menu_id`, `to_menu_id`)
and `task_copy_menu` (params `from_menu_id`, `to_menu_id` — clones an existing menu's whole group/item
structure, a good starting point for a new platform variant of one you already have) and
`task_delete_menu` (params `branch_id`, `menu_id`) round out the lifecycle.

### Groups

| Entity | Create | Mandatory params | Then edit directly |
|---|---|---|---|
| `list_bar_grp` | `task_create_list_bar_grp`, bound to `list_bar_tree` | `list_bar_grp_id` (optional `icon_id`) | `list_bar_grp_description`, `order_no` |
| `tile_grp` | `task_create_tile_grp`, bound to `tile_tree` (sets no description or order — edit both afterwards) | `tile_grp_id` | `tile_grp_description`, `order_no`, `icon_id` |
| `module_grp` | *(no bound task — plain add)* | — | all fields, including `grp_module_grp_id` for nesting, and `icon_id` |

A tile group belongs on a tile menu only. The Software Factory accepts a `tile_grp` under a list-bar
menu without complaint — never put one there.

All three group types carry an `icon_id` — set one deliberately as part of creating the group (the
shared business category it represents, e.g. Sales/Warehouse/Finance), per
`thinkwise-sf-icons`, rather than leaving it blank because the field itself is optional.

**But if `menu.icon_id` / `list_bar_grp.icon_id` writes fail with `403` (`staging_request_failed`)
or `lookup_not_found`, the model has no icon repository yet** on a from-scratch
model where `icon` had zero rows. A brand-new model isn't seeded with icons; every `*_icon_id`
assignment fails until an icon-set base model is linked and merged (see
`thinkwise-sf-icons`). Treat this 403 as "no icon repo", not a permissions problem:
either link an icon set first (a prerequisite step), or ship the menu/groups with blank icons and
say so. When the repo *does* exist, set `icon_id` by its integer id with `value_kind: "data"` — the
`icon.icon_look_up` lookup has no key to select a bare number by otherwise.

`list_bar_tree`/`tile_tree` are read-oriented "design tree" helper entities mirroring the Software
Factory's own tree view — every group is a root row in it (`parent_list_bar_grp_item_id` blank), every item a child row under its group's `pk_col`. The create-group/create-item bound
tasks are bound to a row in this tree, addressed by its synthetic `pk_col`
(`{model_id}/{branch_id}/{menu_id}/…`) — bind to **any** existing row in the target menu (a group or an
item both work; the task creates the new group at the root regardless of which node you bound to, since
list bar/tile groups can't nest under one another anyway). **For the very first group in a brand-new,
completely empty menu** (no `list_bar_tree`/`tile_tree` rows exist yet to bind to), a plain add directly
on `list_bar_grp`/`tile_grp` is the fallback — **verified live**: staging it as a dependent record
under its parent `menu` (rather than a bare top-level insert) succeeds and correctly pre-populates the
key fields. The same dependent-record-under-parent approach is also the reliable way to bootstrap the
first *item* in a group — see Items below, where it's actually the recommended path generally, not
just for bootstrapping.

### Items

| Entity | Create | Mandatory params | Then edit directly |
|---|---|---|---|
| `list_bar_item` | `task_create_list_bar_item`, bound to `list_bar_tree` | *(none)* | `list_bar_item_description`, `menu_item_type`, `tab_id`/`tab_variant_id` or `report_id`/`report_variant_id` or `task_id`/`task_variant_id`, `order_no` |
| `tile` | Plain add — route depends on the layout (see below); `task_create_tile` exists only as bound variants on `menu_tab`/`menu_task`/`menu_report`/`tile_tree` with 6 mandatory params | — | same fields, plus `tile_size` (`small`=0, `medium`=1, `wide`=2, `large`=3) |

**Verified, easy to miss**: `task_create_list_bar_item` takes **zero parameters** — it creates a shell row
with a system-generated key, unlike `list_bar_grp`'s creation which requires an ID up front.

**Verified live, and it contradicts the zero-parameter appearance above**: `task_create_list_bar_item`
stages with no settable fields at all, but committing it can then fail with a mandatory-field validation
error on `menu_item_type` — a field the task never exposes a way to set. Don't rely on this bound task
for creating items. Instead, create the item as a plain dependent-record add under its parent group (the
same "add under parent" approach used for the group bootstrap case above) — this correctly defaults
`menu_item_type`, and lets `list_bar_item_id`, the target field (`tab_id`/etc.), and `order_no` all be
set in the same staging session before committing.

**Adding a `tile`** — the route differs by domain layout:

- **(Indicium · split-domain)** add it under its `tile_grp` on the variant entity set
  `tile.gui_modeler_tile`.
- **(Indicium · single-domain)** the under-parent add answers `detail_nav_not_found`; add `tile` flat
  with the full key (`model_id`, `branch_id`, `menu_id`, `tile_grp_id`, `tile_id`).

If the listed route is refused, try the other. Don't use `task_create_tile`: on `menu_tab` for a
list-bar menu it answered `403`, and the other bound variants have not been run.

**Send `menu_item_type` before its target** (`0` → `tab_id`/`tab_variant_id`, `2` →
`report_id`/`report_variant_id`, `3` → `task_id`/`task_variant_id`): a target field is hidden while
`menu_item_type` points at another type (it starts at `0`), so a `report_id` or `task_id` sent first is
refused with `field_not_editable` and stops the rest of the write. Likewise send `tab_variant_id` after
`tab_id` — setting the table clears the variant. Tile badges have no entity or field in the write API;
configure them in the Software Factory itself.

**Also confirmed live** — another instance of the general "a multi-field write can silently drop one
field" behavior in `thinkwise-sf-data-model`'s quirks section: `list_bar_item_description`
(and the same thing separately confirmed on `list_bar_grp_description`) can silently revert to `null`
after a *later, otherwise-successful* patch in the same staging session (e.g. right after setting
`list_bar_item_id`/`task_id`) — re-check the description field's value in the response after any
subsequent patch and re-set it if it reverted, rather than assuming a single earlier patch call
permanently stuck. **Re-tested and fixed**: setting the description *last* — after
`list_bar_item_id`/`tab_id` (or `list_bar_grp_id`, for a group) — in one combined `stage_resource` call
avoided the drop entirely; the description held correctly with no follow-up patch needed. Order the
properties this way rather than defaulting to a separate corrective patch.

There is no rename task for `list_bar_item`/`tile` — that's fine, because the generated key isn't
shown to end users; only `list_bar_item_description`/`tile_description` is. **Also verified live**:
leaving that description blank is a legitimate, common choice — the design tree's own `display_value`
falls back to the linked object's name plus a type suffix (e.g. `customer (table)`) when no override
description is set, matching what a real production menu does across every item inspected.

**Verified live, silent-failure trap**: setting `tab_id`/`report_id`/`task_id` (or any lookup field) by
display text can silently fail — no error raised, the field simply stays unset — when the target's
display text carries extra wording beyond its plain identifier (e.g. a table described as
`"Employee schedule (Scheduler subject)"` whose actual id is `employee_schedule`). Always re-check the
field's value in the response immediately after setting it; if it didn't take, force a literal/data-value
match on the identifier instead of relying on display-text resolution.

### Ordering

`order_no` follows the platform's usual 10/20/30… convention with gaps for later insertions (verified
live on both groups and items). **Prefer editing `order_no` directly over the `task_move_*`/
`task_renumber_*` bound tasks** (`task_move_list_bar_item_order_no`, `task_move_list_bar_grp_item`,
`task_renumber_list_bar_grp`, and their tile equivalents), every one of these takes
**zero parameters**, meaning they carry no machine-usable direction/target and are effectively
drag-and-drop artifacts from the designer canvas, not a scriptable reordering API. Resize
(`task_resize_tile_small`/`_medium`/`_wide`/`_large`) is the one exception worth using directly since
the target tile is fully identified by the bound key — but editing `tile.tile_size` directly is simpler
and equally valid, since it's a plain editable field.

### Moving an item to a different group

**Reassigning an item's group is not a field edit** — `list_bar_grp_id` (or `tile_grp_id`) is part of
the item's composite key, so there is no in-place "move" write. The working sequence: delete the item
from its current group (`task_delete_list_bar_item`/`task_delete_tile`), then add it fresh in the new
group by the same route used for creating an item at all (see Items above — for a `tile` that route
depends on the layout), reusing the **same** `list_bar_item_id`/`tile_id`, `tab_id`/`report_id`/`task_id`, and
`order_no` for continuity. This applies whenever reorganizing existing items into a new or different
group — e.g. consolidating reference/lookup tables scattered across several subject groups into one
dedicated group.

### Translating new menus, groups, and items

`menu`, `list_bar_grp`/`tile_grp`/`module_grp`, and `list_bar_item`/`tile` are all translatable
objects. Bound-task creation typically leaves a bracket-placeholder label to translate, but the
dependent-record-add workaround used above sometimes leaves no `transl_object` at all, and a group's
real translation type isn't what its name suggests — see `references/menu_translation_notes.md` for
the verified specifics, the backfill recipe, and the final translation-completeness check.

**Verified live on a dependent-record-add build**: the `menu` row *does* get a bracket placeholder
(`transl_object_transl` `type_of_object = 294`); each `list_bar_grp` *does* too, but under
`type_of_object = 12` (`list_bar`), **not** a `list_bar_grp` type — filter the placeholder scan on
both. The `list_bar_item` rows got **no** `transl_object` at all (expected — an item falls back to
its target object's label, and `list_bar_item_description` overrides that), so a residual
`startswith(transl,'[')` count of zero after filling just the menu + group rows is "done". For a
tile menu: each `tile_grp` gets a translation object of type 87; a `tile` gets none (it shows its
target's label).

A group id doubles as its translation key, so a generic id (`general`, `other`) shares its label with
every same-named group in the model — give it a distinguishing prefix when the label must differ.
Deleting a menu, group or item leaves its `transl_object` rows behind; delete those too (see
`thinkwise-sf-translations`).

### Cross-reference (read-only)

`menu_tab` / `menu_report` / `menu_task` list which tabs/reports/tasks are referenced by which menus
across the whole model — query these before renaming or removing a table/report/task to see every menu
item that would break.

## Bound-task quick reference

| Entity | Bound tasks |
|---|---|
| `menu` | `task_copy_menu`, `task_rename_menu`, `task_delete_menu`, `task_menu_mark_new_object_approved`/`_disapproved`, `task_show_history`, `task_unlink_generated_object` |
| `list_bar_tree` | `task_create_list_bar_grp`, `task_create_list_bar_item`, `task_move_list_bar_grp_item`, `task_go_to_list_bar_tree_item` |
| `list_bar_grp` | `task_delete_list_bar_grp`, `task_rename_list_bar_grp`, `task_renumber_list_bar_grp`, `task_create_all_tables_list_bar_grp` (bulk-populate an *existing* group with one item per table — bound to `list_bar_grp`, so it can't bootstrap a brand-new menu's first group), `task_list_bar_grp_mark_new_object_approved`/`_disapproved`, `task_show_history`, `task_unlink_generated_object` |
| `list_bar_item` | `task_delete_list_bar_item`, `task_move_list_bar_item_order_no`, `task_from_object_to_menu_modeler_list_bar` (UI navigation helper — zero params, not for adding items), `task_list_bar_item_mark_new_object_approved`/`_disapproved`, `task_show_history`, `task_unlink_generated_object` |
| `tile_tree` | `task_create_tile_grp`, `task_create_tile`, `task_move_tile_grp_item`, `task_resize_tile_small`/`_medium`/`_wide`/`_large`, `task_go_to_tile_tree_item` |
| `tile_grp` | `task_delete_tile_grp`, `task_rename_tile_grp`, `task_renumber_tile_grp`, `task_move_tile_grp_order_no`, `task_tile_grp_mark_new_object_approved`/`_disapproved`, `task_show_history`, `task_unlink_generated_object` |
| `tile` | `task_delete_tile`, `task_move_tile_order_no`, `task_renumber_tile`, `task_from_object_to_menu_modeler_tile`, `task_tile_mark_new_object_approved`/`_disapproved`, `task_show_history`, `task_unlink_generated_object` |
| `module_grp` / `module_tree` | *(none — zero bound tasks; plain add/edit/delete only)* |
