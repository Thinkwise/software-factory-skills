# Cube performance in the Universal UI

Loaded on demand from `thinkwise_sf_cubes`.

## Why a cube that was fine in the Windows GUI can be slow in the Universal UI

- **Windows GUI** loads the view's data once and groups and aggregates it client-side. Re-pivoting is
  free, but memory and network cost grow with the dataset.
- **Universal UI** hands grouping and aggregation to Indicium and the database, and loads data on
  demand, one subcategory at a time. That fits browser memory limits, JSON transport overhead, and
  corporate firewalls that drop idle HTTP requests after about 30 seconds.

In the Universal UI, **every expand is a filtered, aggregated query**. Expanding `EU` in a
region-grouped sales cube becomes `where region = 'EU'` plus a `group by`. Whether that filter
reaches the base table or waits for the whole view to be built is decided by predicate pushdown. See
`thinkwise_sf_control_procedures`' `references/sql_style_guide.md`, "Write pushdown-safe queries".

**"Expand all" (2026.1+)** fires every subcategory query at the same time. On a pushdown-friendly
cube that's a convenience. On a view that blocks pushdown, it stalls the cube.

## Do

- Back dimensions and values with pushdown-safe columns of the underlying view.
- Default a cube view to a limited range (the current period) through `cube_view_field_filter`
  defaults instead of years of history. Keep reconciliation in mind (see
  `chart_and_field_placement.md`), and make the scope visible to the user.
- Use `union all`, not `union`, in the underlying view.
- Read the execution plan before assuming a slow cube is a pushdown problem.

## Don't

- Use a window-function (`row_number`/`rank`/…) or `distinct`-derived column as a dimension.
- Expect a filter on an aggregated column, or on a `distinct` view, to push down.
- Reach for a persisted precomputed table as the first fix. It's a last resort (see
  `thinkwise_sf_views`, "Performance").
