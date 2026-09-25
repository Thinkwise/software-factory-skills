# Drawable shapes (Geometric Type Creation) and map tab-variant overrides

Loaded on demand from `thinkwise_sf_maps`.

## Drawable shapes (Geometric Type Creation)

Drawing is the mirror image of data mapping: instead of a column feeding the map, the map feeds a
**task**. Since the map component's shape-drawing tools shipped, users can draw markers, circles,
rectangles, lines and polygons directly on the canvas; each draw action executes the task wired into
the matching `map.*_location_task_parmtr_id` field, passing the drawn geometry as that parameter's
value.

A circle's captured JSON carries one extra key beyond a plain CoordSets ring — `"Radius"`, in meters:

```json
{
  "CoordSets": [ [ { "Lat": 52.20839876100734, "Lon": 5.97939399968484 } ] ],
  "Radius": 63.19832731146133
}
```

Setup steps:

1. **Create a task** whose parameters are the target row's primary key column(s), plus one parameter
   (satisfying the `only_alphanumeric` eligibility above) that will receive the drawn geometry as
   CoordSets JSON — for circles, the receiving control procedure also needs the radius, either as a
   second parameter or parsed out of the same JSON payload depending on how the connector surfaces it.
   (This task, like any new task, starts with a bracket-placeholder translation — see
   `thinkwise_sf_translations` to give it a real label before it reaches an end
   user's toolbar.)
2. **Assign the task as a table task** on the same table the map is defined on, mapping the
   primary-key parameters to their columns (`use_primary_key` on the table-task-creation task, or
   explicit `col_id_n`/`task_parmtr_id_n` pairs).
3. **Write the control procedure** that saves the incoming JSON onto the row — a plain `update`,
   verified pattern:

   ```sql
   -- task parameters: company_id, company_address_id (PK), geofence_coordset (task input, the JSON above)
   update company_address
   set geofence_coordset = @geofence_coordset,
       geofence_data_mapping_type = 3
   where company_id = @company_id
   and company_address_id = @company_address_id
   ```

4. **Wire it into the map**: set the relevant `map.*_location_task_parmtr_id` field (the "Geometric
   Type Creation" setting) to the task parameter created in step 1.

**Known platform gap**: no built-in surface-area or length calculation for a drawn shape (a circle
shows its radius on hover; an irregular polygon does not get an area). If a use case needs it (e.g. a
farm field's area in square meters), compute it from the `CoordSets` coordinates yourself — this is an
open, voted Community idea, not yet shipped; check its status before building a custom workaround.

**Circle sizing is in screen pixels for the rendered marker itself**, distinct from the geographic
`Radius` value captured on draw — the drawing tool's on-canvas circle uses Leaflet's `CircleMarker`,
whose own radius option is pixel-based and does not scale with zoom the way the captured `Radius`
(meters) does. Don't conflate the two when styling vs. when processing captured data.

## Tab-variant overrides

Every one of the four map entities has a `tab_variant_*` counterpart that overrides the table-level
default for one specific tab variant, without redefining the map from scratch:

| Entity | Overrides |
|---|---|
| `tab_variant_map` | Center/zoom and column wiring, per variant |
| `tab_variant_map_base_layer` | Base layer set, per variant |
| `tab_variant_map_overlay` | Overlay set, per variant |
| `tab_variant_map_data_mapping` | Styling, per variant |

Use this when the same table's map needs to look or behave differently depending on which screen opens
it (a compact dashboard summary map vs. a full detail-screen map), without maintaining two physical
map definitions. Each has a matching `_overview` read entity and a `task_reset_tab_variant_map*_overview`
bound task (`task_reset_tab_variant_map_overview`, `task_reset_tab_variant_map_base_layer_overview`,
`task_reset_tab_variant_map_data_mapping_overview`, `task_reset_tab_variant_map_overlay_overview`) to
revert a variant's override back to the table-level default in one call, rather than deleting override
rows individually.
