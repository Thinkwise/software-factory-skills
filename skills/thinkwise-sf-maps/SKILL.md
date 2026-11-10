---
name: thinkwise-sf-maps
description: Reference guide for setting up and maintaining a maps component in a Thinkwise Software Factory model — the map_* entity family, the CoordSets JSON coordinate contract, and per-domain-element styling. Use before configuring a map via an MCP connector with Software Factory access, or before writing a control procedure that builds or parses CoordSets JSON.
---

# Setting Up and Maintaining a Maps Component in the Thinkwise Software Factory

Reference for the maps component's full lifecycle: source column → `map` → `map_base_layer`/
`map_overlay` → `map_data_mapping` → (optionally) drawable-shape task wiring → (optionally) an
external-API pipeline that populates the map's coordinates. The worked examples come from a reference
application (`MAPS_AND_ROUTES`) that implements address geocoding and route calculation.

Apply this whenever an MCP connector with Software Factory access is used to create, inspect, or
troubleshoot a maps component. Domain: split-domain instances `sf/manage_maps` for
`map`/`map_base_layer`/`map_overlay`/`map_data_mapping`; single-domain `sf/software_development` for
everything; otherwise find it with `search_domain_capabilities`. **(Indicium · split-domain)** The
surrounding objects sit in their own domains: `tab`/`col`/`dom`/`ref` in `sf/manage_datamodel`,
`control_proc`/`control_proc_template` in `sf/manage_control_procedures`,
`web_connection`/`web_connection_endpoint` in `sf/manage_webconnections`, `process_flow`/`process_action`
in `sf/manage_process_flows`. Reuse a domain key that already resolved this session.

For general data-modeling rules (naming, domain reuse, reference direction) see
`thinkwise-sf-data-model`. For control-procedure mechanics (code groups, static vs. SQL
assignment, `branch_rdbms_type`, and — critically — the two-step "generate code group" then
"generate object code" sequence) see `thinkwise-sf-control-procedures`; every
control procedure referenced below is created and generated exactly that way. This skill only covers
what's specific to maps.

## What a maps component is

A maps component renders one table's rows as geographic content — pins, lines, circles, rectangles or
polygons — on a tile-based map (Leaflet), modeled once per table (`tab_id`) and reused by every screen
that shows it. It is built from four cooperating entities, all keyed by `(model_id, branch_id,
tab_id, …)`:

| Entity | Cardinality | Purpose |
|---|---|---|
| `map` | one per table | Center/zoom, and which columns feed coordinates, styling, popup, label, and drawn-shape capture |
| `map_base_layer` | many per table | The tile provider(s) underneath everything |
| `map_overlay` | many per table | Optional extra tile layer(s) on top, independently togglable |
| `map_data_mapping` | many per table, keyed by `(dom_id, map_data_mapping_id)` | How each row's geometry is styled, one row per domain element |

A map both **displays** data (rows → styled shapes, driven by `map_data_mapping`) and can **capture**
it (a user draws a shape → a task writes it back, driven by the `*_location_task_parmtr_id` fields on
`map` — see "Drawable shapes" below). These are two independent, optional wiring paths on the same
`map` record; a table can use either, both, or neither (e.g. a purely server-calculated map, like the
route example below, wires neither).

Every one of these four entities also has a `tab_variant_*` counterpart (`tab_variant_map`,
`tab_variant_map_base_layer`, `tab_variant_map_overlay`, `tab_variant_map_data_mapping`) that
overrides the table-level defaults for one specific tab variant — see "Tab-variant overrides" below.

## The CoordSets JSON contract

The map does not read raw latitude/longitude columns directly. `map.latitude_longitude_col_id` must
point at a column producing a small JSON envelope, referred to as **CoordSets**, structured as a list
of coordinate rings — one shape for a point, a line, or a multi-ring polygon:

```json
{ "CoordSets": [ [ { "Lon": "5.979388", "Lat": "52.208479" } ] ] }
```

- A **marker** or **circle** has exactly one ring with exactly one point.
- A **line** has one ring with multiple points, in path order.
- A **polygon**/**rectangle** has one or more rings (outer boundary, optional inner holes).
- A **circle** additionally carries a sibling `"Radius"` key (meters) alongside `"CoordSets"` — see
  "Drawable shapes" below for the full shape.

This column is almost always a **calculated field** (`col.calculated_field_type = expression`,
`col.calculated_field_query` holding the SQL) so it always reflects the row's live coordinates without
a stored duplicate. Verified example, straight from a production table (SQL Server dialect):

```sql
-- col: address.map_entity_coordinates, domain: varchar_max
concat('{ "CoordSets": [ [ { "Lon": "', t1.longitude, '", "Lat": "', t1.latitude, '" } ] ] }')
```

**Check `branch_rdbms_type` before writing this kind of SQL.** See the
`thinkwise-sf-control-procedures` skill for the full dialect-check walkthrough;
the essential rule is: never assume SQL Server syntax works on PostgreSQL, or vice versa — verify
first. Specifically for CoordSets: `concat(...)` works as shown on SQL Server; on PostgreSQL the
equivalent is typically `json_build_object('CoordSets', json_build_array(json_build_array(
json_build_object('Lon', t1.longitude, 'Lat', t1.latitude))))::text` or an equivalent
`jsonb_build_object`/`format` construction.

A calculated field is not the only option: for a table whose geometry is written by an external
process (route calculation, geocoding, a drawn-shape task — see later sections), `map_entity_coordinates`
is instead an ordinary stored column that a control procedure `update`s directly with a hand-built
CoordSets string.

**Transposing `Lon`/`Lat` is a silent, hard-to-notice bug — sanity-check it against a real place.**
Both are ordinary numeric values sitting next to each other in the same `concat`/`json_build_object`
call, so swapping which source column feeds which JSON key produces a string that is still perfectly
valid CoordSets JSON and generates without any error — it just plots every row in the wrong spot (a
verified case: real-world coordinates with `Lon`/`Lat` swapped rendered a Netherlands address in the
Indian Ocean off the Horn of Africa). After writing this expression, check the map against at least
one row whose real-world location you actually know, not just that the column generated and the map
renders *some* pin.

## The map entity family

Batch `get_entity_definition` across `map`, `map_base_layer`, `map_overlay` and `map_data_mapping` —
the object graph is known up front — for fields, keys, enums and bound tasks. What the metadata
won't tell you:

- **`map_data_mapping` matches rows to styling by *domain element*, not by a style column.** The
  element value on the mapped column selects the marker/colour, so the column must use a domain that
  has elements defined; a free-text column cannot drive per-row styling.
- **`allow_drag_drop` on the data mapping** is what enables marker dragging — it is *not* part of the
  generic `drag_drop*` family used elsewhere in the model.
- A base layer and an overlay are different things: the base layer is the map background, overlays
  sit on top and can be toggled.

For the full per-entity field reference and the domain-element matching contract, read
`references/map_field_reference.md`.

## Setting up a basic map — step by step

0. **Confirm scope with the user before creating anything** — which table needs the map, what
   geometry types it needs (marker/line/polygon/rectangle/circle, or a mix), the initial center/zoom,
   which tile provider(s) to use, and whether end-user drawing (Geometric Type Creation) is needed.
   This is `thinkwise-sf-base`'s "Shared conventions" — Confirm-before-mutate and
   Ask, don't default — applied to a map specifically: don't create the coordinate column, the `map`
   row, or anything else in the steps below until this is settled.
1. **Confirm the connector's actual domain keys** for maps / data model / control procedures from
   the connector's server instructions (see `thinkwise-sf-base`) — one domain on a single-domain
   instance, several on a split-domain one. Don't call `get_available_domains` for this.
2. **Get (or build) a CoordSets-producing column** on the target table — a calculated field per "The
   CoordSets JSON contract" above, checking `branch_rdbms_type` first if hand-writing the SQL.
3. **Create the `map` row** for the table. Send `tab_id` first — it clears the column fields — and
   set the three column fields after it: `latitude_longitude_col_id` to that column,
   `data_mapping_col_id` to a domain-based column, `popup_col_id` to whatever should show on click,
   and `initial_latitude`/`initial_longitude`/`initial_zoom_level` (mandatory) from what the user confirmed in
   step 0 — if that wasn't pinned down yet, ask for the initial center/zoom now, or infer it from a
   known reference row already confirmed with the user, rather than picking an arbitrary default.
4. **Add at least one `map_base_layer`** with a working tile URL template, a zoom range that matches
   what the provider actually serves, and (for most public providers) `attribution_html`. If the tile
   provider(s) weren't already confirmed in step 0, ask which to use rather than picking one
   unilaterally.
5. **Add one `map_data_mapping` row per element** of the domain used in step 3's `data_mapping_col_id`
   — pick `geometric_type` per element; for `line`/`polygon`/`rectangle`/`circle` elements, also set
   border/fill styling, decoding/encoding colors per the formula below; for `marker` elements, set an
   `icon` on the element instead (see the marker exception above) and leave color fields untouched.
   Don't *add* these rows: once the `map` row and its `data_mapping_col_id` exist, the Software
   Factory already lists one candidate row per domain element in `map_data_mapping_overview`
   (`allow_add = false`, `allow_update = true`), with `show_map_data_mapping` false.
   - **(Indicium · single-domain)** Edit each candidate by its full key (`model_id`, `branch_id`,
     `tab_id`, `dom_id`, `map_data_mapping_id`): set `geometric_type`, the styling and
     `show_map_data_mapping` = true. The edit turns it into a real `map_data_mapping` row; read it
     back there. A flat `map_data_mapping` add stages but leaves every key field read-only and null,
     and an add under `map` gives `detail_nav_not_found` — neither can be completed.
   - **(Indicium · split-domain)** Every add route failed, and the `_overview` edit was rejected on
     commit. Try the overview edit once; if it is refused, this is a manual step in the Software
     Factory.
6. **Verify the eligible domain elements' `elemnt_id`s exactly match the `map_data_mapping_id`s
   created** — a mismatch silently leaves some rows unstyled rather than erroring.
7. Only if the table needs end-user drawing: wire the relevant `add_<shape>_task_id` and then
   `<shape>_location_task_parmtr_id` field(s) on `map` — see "Drawable shapes" next.
8. Only if coordinates come from an external service rather than user input or plain columns: build
   the web-connection/process-flow/control-procedure pipeline — see "External-API pattern" below.

## Drawable shapes and per-variant overrides

A map can let users draw points, lines and polygons back into the model, and each table variant can
override the map's own settings.

For drawable shapes (Geometric Type Creation, which geometry types are supported, and how drawn
shapes round-trip into CoordSets) and the map tab-variant override fields, read
`references/drawable_shapes_and_variants.md`.

## External-API pattern: geocoding and route calculation

For populating a map's coordinates from an external service instead of user input — a table task
(dummy trigger) → process flow → `web_connection` call → task → control procedure that parses the
response and writes CoordSets, including the verified `process_action` sequence, `web_connection`/
`web_connection_endpoint` field reference, and the full openjson/PostgreSQL JSON-parsing SQL examples —
read `references/external_api_pattern.md`.

## Bound-task quick reference

Exact task names verified on the map entities — use these rather than guessing when a connector needs
to mutate/inspect map configuration programmatically:

| Entity | Bound tasks |
|---|---|
| `map` | `task_delete_map`, `task_show_history`, `task_unlink_generated_object` |
| `map_base_layer` | `task_copy_map_base_layer`, `task_delete_map_base_layer`, `task_rename_map_base_layer`, `task_show_history`, `task_unlink_generated_object` |
| `map_overlay` | `task_copy_map_overlay`, `task_delete_map_overlay`, `task_rename_map_overlay`, `task_show_history`, `task_unlink_generated_object` |
| `map_data_mapping` | `task_show_history`, `task_unlink_generated_object` (no copy/rename; rows come from the domain's elements, see step 5) |
| `tab_variant_map` / `_base_layer` / `_overlay` / `_data_mapping` | `task_reset_tab_variant_map_overview`, `task_reset_tab_variant_map_base_layer_overview`, `task_reset_tab_variant_map_overlay_overview`, `task_reset_tab_variant_map_data_mapping_overview` — revert an override back to the table-level default |

`task_copy_map_base_layer` / `task_copy_map_overlay` take `from_tab_id`/`from_map_base_layer_id`/
`to_tab_id`/`to_map_base_layer_id` (or the overlay equivalents) — useful for cloning a working tile
setup onto a new table rather than re-typing URIs and zoom ranges.

The delete tasks leave the object's `transl_object` rows behind — delete those too (see
`thinkwise-sf-translations`).

## Known pitfalls (Community-verified)

- **Pagination hides markers, not a hard limit.** The map only renders rows on the currently loaded
  page — if locations are silently missing, raise the table's/task's page size before assuming a
  platform cap.
- **First load can center on (0, 0) ("Null Island").** A map showing a route has been reported to
  open there on the very first render, then auto-fit correctly on every later open — a confirmed bug,
  not a modeling error. Setting an explicit `initial_latitude`/`initial_longitude` may mask it for
  small extents.
- **Max zoom is the tileset's limit, not the GUI's** — see `map_base_layer`/`map_overlay` field
  reference above.
- **No bearer/OAuth2 tile layers directly** — see the same section; use a proxy.
- **Data-mapping legend order/visibility toggle has had cross-GUI inconsistencies** — verify on the
  actual target GUI and version rather than trusting the modeled order alone.
- **Circle drawing size is pixel-based on-canvas**, distinct from the geometric `Radius` captured in
  the drawn shape's JSON — don't conflate visual size with the meters value.
- **No built-in shape area/length calculation** — compute from `CoordSets` yourself if needed; watch
  the relevant Community idea for platform support.
- **A `marker` row's color/width/opacity fields are hidden and nulled by the platform itself** — style
  a marker via its domain element's `icon` instead, not via `map_data_mapping`'s color fields. See the
  marker exception under the `map_data_mapping` field reference above.
- **`Lon`/`Lat` transposed in a CoordSets expression produces no error, just a silently wrong pin
  location** — verify against a known real-world coordinate, not just that the map renders something.

## Pre-flight checklist

- `map.data_mapping_col_id`'s domain element IDs must exactly match the `map_data_mapping_id`s
  created for that `dom_id` — a mismatch silently leaves rows unstyled, it does not error.
- For `marker` rows, don't set `border_color`/`fill_color`/etc. at all — the platform hides and nulls
  them; set the domain element's `icon` instead. Decode/encode `border_color`/`fill_color` as
  signed-32-bit ARGB using the ⟨alpha, red, green, blue⟩ formula above only for the other four
  geometric types.
- `map_data_mapping` rows are not added: edit the pre-listed candidate per element in
  `map_data_mapping_overview` **(Indicium · single-domain)**; on refusal a manual step in the
  Software Factory **(Indicium · split-domain)** — see step 5.
- `allow_drag_drop` is only shown (and only applies) for `marker` rows; it is hidden for the other
  geometric types.
- `map.initial_zoom_level` is mandatory; set each `add_<shape>_task_id` before its
  `<shape>_location_task_parmtr_id` (hidden until the task is set).
- `map_base_layer`/`map_overlay` `max_zoom_level` must match what the tile provider actually serves,
  not an aspirational value.
- Bearer/OAuth2-secured **tile layers** need a proxy; bearer/OAuth2-secured **API calls** for
  geocoding/routing are natively supported via `web_connection.authentication_type`.
- The five `map.*_location_task_parmtr_id` fields only accept task parameters passing the
  `only_alphanumeric` eligibility filter — confirm before assigning.
- The dummy-trigger-task pattern (`task_type_id = 'DUMMY'`, all parameters hidden) is expected and
  correct for a process-flow-driven map data source — don't add UI-visible fields or dynamic-model
  code to it; the logic belongs in the process flow and its control procedures.
- Verify the actual process-variable name carrying a web connection's raw response body
  (`@response_http_content` in the verified reference model) against the connector's own process-flow
  variable list — don't port it blindly.

