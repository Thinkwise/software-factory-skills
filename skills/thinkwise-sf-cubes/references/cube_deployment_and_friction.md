# Cube screen types, user customization, modeling friction, and a worked example

Loaded on demand from `thinkwise_sf_cubes`.

## Screen types, components, and per-variant overrides

The default cube-capable screen types are `cube`, `cube_horizontal`, and `cube_no_fields`; the
available components are **Pivot table**, **Chart**, **Cube panel**, and **Cube view bar** — assigning
these to a table's screen type follows the exact same mechanics as any other screen type (pick from
what already exists in the model; creating a new screen type isn't supported via MCP — see
`thinkwise_sf_build_planner`). The platform removes the Pivot table component
automatically whenever no cube definition exists for the effective subject — if a screen looks like
it's missing its pivot, check that a `cube` row actually exists for that table before assuming a
component-wiring bug.

### Per-table-variant overrides

Same field-level inheritance pattern documented generically in `thinkwise_sf_variants`
(no Setup/snapshot step — plain override, tracked until it diverges):

- `tab_variant_cube_overview` (`cube_id` + `tab_variant_id`) — per-variant `default_cube_view_id` and
  `allow_dragging_fields`; `task_reset_tab_variant_cube_overview` reverts to inheriting the default.
- `tab_variant_cube_view_overview` (`cube_id` + `tab_variant_id` + `cube_view_id`) — per-variant
  `show_cube_view`, `screen_area_id`, `custom_display_type`, `conditional_layout_code`;
  `task_reset_tab_variant_cube_view_overview` reverts it.

Use these when different audiences of the same table need a different default view or a different
subset of visible views (e.g. an executive variant showing only two high-level views vs. an
analyst variant showing all of them with the Cube panel enabled) — not a reason on its own to build a
second cube.

## User customization — the Cube panel

When `cube.allow_dragging_fields` (or its per-variant override) is on and the role has
`dragging_fields_granted`, end users can rearrange fields between areas, change sort/chart settings,
and save their own personal cube views with their own filters — without touching the model. Modeled
views should still stand on their own as good starting points; a personal view can go stale when the
underlying cube fields change later, so treat this as a reason to periodically review, not a reason
to under-invest in the modeled views.

## Known SF-modeling friction (from Thinkwise Community feedback)

Worth knowing going in, since these are reported pain points rather than bugs in your modeling:

- **No live preview in the Software Factory.** Cube views can't be previewed while modeling — the
  documented workaround is building the view once in the actual running application, then
  replicating that field arrangement back into the SF. Thinkwise has stated (per a 2024 community
  reply) that a write-back/WYSIWYG editor from the running app into the SF is a longer-term direction,
  not something shipped yet — don't assume a preview or write-back capability exists.
- **Interval auto-mapping can misfire** — community reports of week/month/day interval detection
  picking the wrong granularity on the generated proposal. Always manually verify
  `type_of_grp_interval` on every interval dimension rather than trusting the generated default.
- **The 2025.1 release specifically addressed several of these complaints**: cube fields are now
  split into separate Dimensions/Values tabs (matching the `dimension`/`measure` split above), and a
  visual "Cube set-up panel" (the `cube_view_field_set_up` entity, drag-drop area assignment) was
  added. If working against an older branch/model version, some of this may not be present yet.
- Users have reported the four area names (Filters/Categories-Rows/Series-Columns/Values) not always
  matching what they expected from the running app's terminology, and that assigning a field to one
  area can visually surface elsewhere unexpectedly — when a placement looks wrong after a
  `patch_resource` on `cube_area`, re-query `cube_view_field` to confirm the stored value rather than
  trusting a stale prior read.
