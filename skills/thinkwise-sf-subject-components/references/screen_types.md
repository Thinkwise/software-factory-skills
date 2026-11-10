# Building a screen type

Prefer an existing screen type: query `screen_type` filtered by `model_id`/`branch_id` and offer what
fits (see `thinkwise-sf-build-planner`'s interaction-surface step). Build a new one only when nothing
existing has the requested arrangement — and agree the component tree with the user first (Plan
first / Confirm-before-mutate in `thinkwise-sf-base`).

Verified through the write API on SF 2026.2 (2026-10-30): a `screen_type` plus a Splitter → Tab →
TabPage → Grid tree was created, committed and assigned as a table's `main_screen_type_id`.

## Creating it

1. Add `screen_type` under `branch` with `screen_type_id` and `screen_type_description`. Leave the
   `has_*` flags alone — they are hidden and derived from the components. The name becomes a
   translation object (type 164) once the branch has application languages.
2. Add each component as a `screen_component` **under the `screen_type`**, naming the detail
   navigation `detail_ref_screen_type_screen_component` — the parent has two navigations (the other is
   a `_modeler` variant), so the add fails without an explicit `detail_nav`.
3. Assign it: `tab.main_screen_type_id` (or `detail_`/`zoom_`/`popup_screen_type_id`, or the
   variant's `apply_*_screen_type_id` + id) accepts the new id once the screen type exists. An earlier
   403 on this field came from pointing it at a screen type that didn't exist yet.

## `screen_component` fields

| Field | Notes |
|---|---|
| `screen_component_id`, `order_no` | Settable and mandatory; `abs_order_no` is read-only |
| `screen_component_type_id` | Case-sensitive id, pass with `value_kind: "data"`: `Splitter`, `ActionBar`, `CombinedFilter`, `Form`, `Grid`, `Cardlist`, `Tree`, `Tab`, `TabPage`, `DetailTabPage`, `Scheduler` (verified: Splitter, Tab, TabPage, Grid) |
| `parent_screen_component_id` | Plain data value — empty for the root |
| `height`/`height_unit`, `width`/`width_unit` | **Mandatory**. Unit: pixels `0`, percentage `1` |
| `region` | **Mandatory**. North `0`, south `1`, east `2`, west `3` |
| `tab_page_label` (+ `tab_page_icon_id`) | Only editable on a `TabPage`; hidden on every other type, so sending it there is refused and stops the rest of the write |
| `tab_orientation` | Only editable on a `Tab`: horizontal `0`, vertical `1` |
| `component_action_bar_enabled` | Only editable on a `Grid`; hidden on `Form`, so sending it there is refused and stops the rest of the write |
| `primary_action` | Editable on every type |

A single full-size component takes `height` 100, `height_unit` 1, `width` 100, `width_unit` 1,
`region` 0.

## Check the tree yourself

**The Software Factory accepts a broken component tree without error**, so check it after building:

- exactly one root; every `parent_screen_component_id` exists in the same screen type; no cycles;
- a `Tab` holds only `TabPage`/`DetailTabPage` children; a `TabPage` holds exactly one child;
- a `Splitter` holds its bars plus one or two panes;
- `Form`, `Grid`, `Cardlist`, `Tree`, `Scheduler` and `DetailTabPage` hold nothing;
- at least one data component (Form, Grid, Cardlist, Tree, Scheduler);
- a table or variant actually uses the screen type.

## Reported, not re-verified

- Deleting a screen type that a variant uses succeeds silently and clears the variant's
  `main_screen_type_id` — check where it's used before deleting. The delete leaves the screen type's
  `transl_object` row (type 164) behind; delete it too (see `thinkwise-sf-translations`).
- The standard generated screen types include no form-only, grid-only or tree-only layout.
- `tab_page_label` is a translation key shared across screen types (reported as type 229; the
  `type_of_object` enum names 229 `screen_area`, so read back which type actually appears).
- Component properties, breakpoints and screen areas have not been verified through the write API —
  set them in the Software Factory itself and list that as a manual step.
