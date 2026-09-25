# Colour and font fields — legacy vs. Universal UI

Loaded on demand from `thinkwise_sf_conditional_layouts`.

## Colour and font fields — legacy vs. Universal UI

Every layout family carries a **legacy, single-value Windows-GUI field** alongside a **Universal-UI
theme pair**, confirmed on `conditional_layout`/`task_conditional_layout`:

| Concept | Legacy (Windows GUI) | Universal UI (set both) |
|---|---|---|
| Background colour | `background_color` | `background_color_light` + `background_color_dark` |
| Font colour | *(no legacy equivalent — asymmetric)* | `font_color_light` + `font_color_dark` |
| Font family/size | `font_id` → `font` lookup (`font_info` string only) | `font_size` enum (`L`=0, `XL`=1) |

For new work targeting Universal UI, ignore `background_color`/`font_id` and always set both the light
and dark variant of whichever colour you're using. Don't copy one theme's colour into the other without
checking contrast — a light-yellow background with dark text can disappear in dark mode; a saturated
red background can overwhelm; grey "inactive" text can become unreadable. Test normal, selected,
focused, hover, and edit states, with real data density.

### Computing a colour value without the Software Factory's own colour picker

`background_color_light`/`_dark` and `font_color_light`/`_dark` store a plain signed `Edm.Int32` with
no documented encoding. Verified live (on `scheduler_view_conditional_layout.background_color_light`/
`_dark`, a sibling field with the identical shape): assuming full opacity, the stored value is

```
signed_int32 = (R * 65536 + G * 256 + B) - 16777216
```

where `R`/`G`/`B` are each 0–255 from the desired colour's hex value. Confirmed against a real example:
`-7223041` decodes to `0x91C8FF` (a light blue), matching a cell colour named for that shade.

**Prefer setting the colour through the Software Factory's own colour setting/picker when that UI is
reachable** — this formula is the fallback for a connector/API-only session with no UI access, not a
replacement for the platform's own colour management.
