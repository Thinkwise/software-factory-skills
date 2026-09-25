# Diagrams in a Thinkwise data model

Loaded on demand from `thinkwise_sf_data_model`. Diagram **writes are not possible**
through a metadata-driven modeling API — this file covers the design rules for when a human
maintains them in the Software Factory.

**"Domain" here means a functional/subject area** — an informal business grouping like "Sales", "HR",
or "Finance" — not a Software Factory object in its own right (don't confuse it with the DTTP `dom`
entity in the "Domains" section below, which is a data type, not a diagram scope). Software Factory has
no dedicated entity for this kind of grouping — a **diagram** (`diagram`, plus `diagram_tab`/`diagram_ref`
placement rows) *is* how a functional/subject area gets represented in the model, in principle one
diagram per area.

### Currently not possible via this kind of API — don't attempt it

**Placing a table (or a reference) onto a diagram is currently blocked on every write path tried**, both on a metadata-driven staging API and on a direct entity write:
- `task_create_own_diagram` is rejected before any field can even be set.
- A direct add to `diagram_tab` (the join row that positions a table on the canvas) is rejected even
  after supplying the required parent context.
- `task_add_table_to_diagram` itself takes **zero parameters** — there is no way to target a specific
  table with it even in principle.

**Don't create a new diagram, and don't try to add a table or reference to an existing one.** Creating
the bare `diagram` record itself (a plain add, with nothing placed on it) does commit fine, but an
empty diagram isn't useful, so there's no reason to create one either while this is blocked. Treat all
diagram/table/reference placement — including via the other bound tasks listed below
(`task_one_level_deeper`/`task_one_level_higher`/`task_create_link_table`/`task_copy_diagram`/
`task_import_into_own_diagram`) — as a manual step in the Software Factory's own UI. If a request would
otherwise call for adding to or creating a diagram, say so explicitly and describe the manual step for
the user, rather than attempting the API call and only falling back once it fails.

The subsections below still describe the *design* decision (which diagram a table or reference should
logically live on, when a diagram has outgrown itself) — that reasoning is still worth handing to the
user as part of the manual step. Nothing in them should be executed as an actual write against
`diagram`/`diagram_tab`/`diagram_ref` until this limitation is lifted.

### Adding a new table (subject): which diagram does it belong on?
- Identify which functional/subject area the new table belongs to.
- **If a diagram already exists for that area**, tell the user the table should be added to it as a
  manual step (see above) — don't call `task_add_table_to_diagram`.
- **Only recommend a new diagram** — for the user to create manually via `task_create_own_diagram`
  then `task_rename_diagram` in the Software Factory UI — **when the table starts a genuinely new
  functional/subject area** not represented by any existing diagram yet.
- **Still flag every newly created table's diagram placement as an open item**, even though it can't be
  done through the API right now — an undiagrammed table is invisible to anyone reviewing the model
  visually, so don't let this limitation become a silent reason nothing ever gets diagrammed.

### Adding a new reference: which diagram does it belong on?
- **If both tables of the reference already appear on the same area's diagram**, tell the user the
  reference should be added there too (manually) so the relationship is visible where the tables
  already are.
- **If the reference crosses two different areas' diagrams** (e.g. `sales_order.employee_id` →
  `employee`, where `employee` lives on the "HR" diagram and `sales_order` on "Sales"), recommend
  placing the reference on the diagram of the table that conceptually owns the relationship (usually
  the referencing/child table's area) and pulling in just that one related table, rather than merging
  two areas into one diagram — again, as a manual step, not an API call.

### When a diagram has genuinely outgrown itself
- A diagram that's grown past the point of being readable at a glance (dozens of tables, dense crossing
  reference lines) is a signal to split it — there's no fixed table-count threshold; judge it by whether
  it's still doing its job as an at-a-glance picture of one functional/subject area.
- Splitting is not "shrink every diagram to some size" — keep the split aligned to real functional
  boundaries. If a diagram is oversized because its area genuinely covers more than one concern, split
  along those functional lines (e.g. "Sales" into "sales_ordering" and "sales_reporting") rather than an
  arbitrary table-count cut. This is design guidance to hand to the user; the actual split/copy work
  (`task_copy_diagram`/`task_import_into_own_diagram`) is a manual step for the same reason as above.

### Bound tasks on `diagram` — for reference only, not currently usable through this kind of API
- `task_add_table_to_diagram` — place one table onto a diagram.
- `task_one_level_deeper` (given a `tab_id` already on the diagram) — pulls in every table one hop away
  via a reference to/from it.
- `task_one_level_higher` — the reverse; trims tables one hop out, for narrowing a diagram back down.
- `task_create_link_table` — models a many-to-many link table directly from the diagram, wiring it to
  two tables already placed on it.
- `task_copy_diagram` / `task_import_into_own_diagram` — duplicate or merge an existing diagram's
  layout rather than starting a split or overlapping diagram from scratch.

These still exist in the metamodel and may work directly in the Software Factory's own UI — only the
API write path is confirmed blocked (see above). Re-verify before relying on this list again if the
platform/connector version changes.

