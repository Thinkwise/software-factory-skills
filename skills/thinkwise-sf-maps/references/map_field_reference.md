# map / map_base_layer / map_overlay / map_data_mapping field reference

Loaded on demand from `thinkwise_sf_maps`.

## `map` — field reference

Keyed by `(model_id, branch_id, tab_id)` — one row per table that has a maps component.

| Column | Purpose |
|---|---|
| `initial_latitude` / `initial_longitude` / `initial_zoom_level` | Where the map centers when first opened, if not auto-fitting to data |
| `latitude_longitude_col_id` | The CoordSets-producing column (above) |
| `data_mapping_col_id` | The domain-based column selecting which `map_data_mapping` style applies to a row — see next section for the exact matching contract |
| `popup_col_id` | Column shown in the shape's popup on click — often an HTML calculated field |
| `use_custom_label_col_id` (flag) / `label_col_id` | Optional always-visible label per shape, instead of only-on-click popup content |
| `marker_location_task_parmtr_id`, `line_location_task_parmtr_id`, `polygon_location_task_parmtr_id`, `rectangle_location_task_parmtr_id`, `circle_location_task_parmtr_id` | **Geometric Type Creation** wiring — which task parameter receives the coordinates when a user draws that shape type on the map. Leave all five unset for a purely display/server-calculated map (verified: the reference model's two maps used none of them). See "Drawable shapes" below |

**Lookup restriction on the five `*_location_task_parmtr_id` fields**: their navigation properties
target `task_parmtr.only_alphanumeric` — only task parameters passing that filter are selectable.
Confirm a candidate parameter satisfies it (via `get_entity_definition`/`get_domain_definition`
before assigning; don't assume a parameter is eligible just because it exists) rather than assuming
any task parameter can be wired in.

## `map_base_layer` / `map_overlay` — field reference

Both are XYZ tile layers with the same shape; overlays add opacity and menu visibility since they're
meant to be independently toggled on top of a base layer. Keyed by `(model_id, branch_id, tab_id,
map_base_layer_id)` / `(…, map_overlay_id)`.

| Column | Purpose |
|---|---|
| `map_base_layer_uri` / `map_overlay_uri` | XYZ tile URL template, e.g. `https://…/{x}/{y}/{z}` or a provider-specific query string form |
| `order_no` | Stacking order among multiple layers |
| `min_zoom_level` / `max_zoom_level` | Zoom range **the tileset itself serves** — not a client-side UI limit. Setting this higher than the provider actually supports returns blank/upscaled tiles, it does not unlock more detail |
| `tile_size` | Pixel size of each tile, if the provider deviates from the 256px default |
| `attribution_html` | Attribution shown in the map's corner — mandatory for most public tile providers' terms of use |
| `show_map_base_layer` / `show_map_overlay` | Default visibility |
| `opacity` *(overlay only, `Edm.Byte` 0–255)* | Transparency so the base layer stays visible underneath |
| `show_in_menu` *(overlay only)* | Whether users can toggle this overlay themselves |

**If the user hasn't specified which tile provider(s) to use, ask** — per
`thinkwise_sf_base`'s "Ask, don't default" convention, don't pick one unilaterally
just because a URL template is easy to construct.

Verified example — three base layers on one table, sharing one URL template with only the `lyrs` query
parameter changed (Google classic tile endpoint: `m` = road, `p` = terrain, `y` = hybrid/satellite),
all zoom 0–18:

```
road:      https://mt0.google.com/vt/lyrs=m&hl=en&x={x}&y={y}&z={z}
terrain:   https://mt0.google.com/vt/lyrs=p&hl=en&x={x}&y={y}&z={z}
satellite: https://mt0.google.com/vt/lyrs=y&hl=en&x={x}&y={y}&z={z}
```

Overlays are optional — reach for one only when a layer needs to be independently toggled and
opacity-blended over whichever base layer is active (traffic, weather, custom raster/heat data).

**Bearer/OAuth2-token-authenticated tile sources are not supported directly.** The component is built
for a long-lived token embeddable in the URL (a query-string API key, as above). A short-lived bearer
token needing an OAuth2 refresh flow can't be handled by the browser/server tile request — front it
with your own proxy web service that injects and renews the header, and point `map_base_layer_uri` /
`map_overlay_uri` at the proxy instead of the token-protected source directly.

## `map_data_mapping` — field reference and the domain-element matching contract

Keyed by `(model_id, branch_id, tab_id, dom_id, map_data_mapping_id)` — **one row per element of the
domain referenced by `map.data_mapping_col_id`.** The matching contract, verified against a real
model: the column `map.data_mapping_col_id` points at must use domain `dom_id`; each
`map_data_mapping_id` must equal one of that domain's element IDs (`elemnt.elemnt_id`). A domain with
4 elements (verified: an `IMAGE_COMBO`-controlled `varchar` domain, `no_of_elemnt = 4`) needs exactly
4 `map_data_mapping` rows to give every element a style — an element with no matching row has no
defined rendering.

| Column | Purpose |
|---|---|
| `geometric_type` (`Edm.Byte`, enum) | `marker` = 0 · `line` = 1 · `polygon` = 2 · `rectangle` = 3 · `circle` = 4 |
| `border_color` / `fill_color` (`Edm.Int32`) | **Signed 32-bit ARGB** — see decoding formula below |
| `border_width` | Outline width |
| `border_opacity` / `fill_opacity` (`Edm.Byte`, 0–100) | Separate from the color's own alpha channel — both are applied |
| `allow_drag_drop` (flag) | Lets a user reposition this shape by dragging it on the map, writing the new position back through drag/drop logic — **not** the same mechanism as the generic `drag_drop`/`drag_drop_parmtr`/`drag_drop_matrix` entity family covered in `thinkwise_sf_subject_components`; this is a map-specific flag with no task/parameter wiring of its own |
| `show_map_data_mapping` (flag) | Default on/off state for this style's legend/layer entry — **must be turned on for the style to actually render on the map at all**; don't assume it defaults to visible, verify it explicitly on every row |

### A `marker` row ignores all its color/width/opacity fields — style comes from the element's icon instead

**Verified directly against the platform's own Layout and Default control procedures for
`map_data_mapping`** (read from the Software Factory's own meta-model, not inferred): the moment
`geometric_type` is set to `marker` (0), a Default-type control procedure clears `border_color` and
`fill_color` to `null` and resets `border_width`/`border_opacity`/`fill_opacity` to fixed baseline
values, and a Layout-type control procedure hides all five fields (`border_color`/`border_width`/
`border_opacity`/`fill_color`/`fill_opacity`) on the form for the rest of that row's life. Don't spend
effort choosing marker colors — they're discarded. A marker's actual visual appearance is driven by
the **domain element's own `icon`/`icon_id` field** (on `elemnt`, the same row `map_data_mapping_id`
must match), not by anything on `map_data_mapping` itself. Only `line`/`polygon`/`rectangle`/`circle`
rows actually use the color/width/opacity fields below.

**The built-in icon catalog is not reliably queryable through a metadata-driven connector** — a
model's `icon`/`icon.icon_look_up` entity can return zero rows even when icons are visibly in use
elsewhere in that same model. This is now explained by `thinkwise_sf_icons`: nearly every
icon-bearing entity, `elemnt` included, actually carries **two** independent mechanisms — an `icon_id`
foreign key into the shared repository, and a local `icon`/`icon_data` file uploaded straight onto the
row. A model whose markers were all styled via the local upload path (never entered into the shared
`icon` repository) will show icons rendering fine in the app while the `icon` entity itself sits empty.
Don't try to enumerate or guess a valid `icon_id` from a possibly-empty repository query. **If the user
hasn't specified which icon a marker should use, ask** (or hand them the picker) — per
`thinkwise_sf_base`'s "Ask, don't default" convention, and per
`thinkwise_sf_icons`'s own rule to ask rather than guess when no confident match exists —
rather than choosing one unilaterally.

### Decoding/encoding `border_color` and `fill_color` (non-marker geometric types only)

These are stored as a **signed 32-bit integer holding an ARGB value**, alpha in the high byte:

```
unsigned = value if value >= 0 else value + 2**32
alpha = (unsigned >> 24) & 0xFF
red   = (unsigned >> 16) & 0xFF
green = (unsigned >> 8)  & 0xFF
blue  =  unsigned        & 0xFF
```

To encode a desired ARGB back into the field, do the reverse and re-sign if the unsigned value exceeds
`2**31 - 1`:

```
unsigned = (alpha << 24) | (red << 16) | (green << 8) | blue
value = unsigned if unsigned < 2**31 else unsigned - 2**32
```

Verified worked example from a production `map_data_mapping` row styling a route line: field value
`-16776961` → unsigned `4278190335` → `0xFF0000FF` → alpha `FF` (opaque), red `00`, green `00`, blue
`FF` — solid opaque blue. Get this formula wrong and a control procedure or staged write silently
produces the wrong color (e.g. transparent, or a completely different hue) with no error at any step.

A single table's map_data_mapping rows can mix geometric types freely under one domain — verified:
one table used a 4-element domain where three elements were markers (`origin_marker`,
`destination_marker`, `waypoint_marker`) and the fourth was a `line` (the calculated route path),
letting one map render both point and path geometry from the same coordinate column.

**Legend/layer-ordering caveat**: Community reports note inconsistencies between how `map_data_mapping`
elements are ordered/sequenced in the Software Factory vs. how they render in a running app, and that
`show_map_data_mapping` hasn't always behaved as expected across Windows GUI vs. Universal GUI —
verify actual rendered behavior on the target GUI and platform version rather than trusting the
modeled order_no/flag alone.
