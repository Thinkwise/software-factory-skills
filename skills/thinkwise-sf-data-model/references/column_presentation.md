# Column presentation — grid visibility, form/grid groups, sort, search, filter

Loaded on demand from `thinkwise_sf_data_model`.

## Grid column visibility

**A grid should only show the columns a user is likely to need at a glance** — not every column the
table has. Decide each column's `grid_type_of_col` (`editable`/`read_only`/`hidden`) deliberately
rather than leaving it at its default (which behaves as `editable`, i.e. visible, for every column):

**There is also a third, base-level field, `col.type_of_col`, separate from both
`grid_type_of_col` and `form_type_of_col`**, and easy to miss since only the
grid/form-specific pair is documented above. In the Software Factory's own column-properties
screen it surfaces simply as "Column type", grouped with general settings like domain/primary
key/mandatory rather than anywhere near the grid- or form-specific settings, which is why it's
easy to change the presentation-specific fields and still leave this one at its default. Same
`editable`/`read_only`/`hidden` enum. Set it together with `grid_type_of_col`/`form_type_of_col`
whenever a column's visibility decision is meant to hold everywhere (not just one presentation
surface) — including the inherited-primary-key carve-out below.

- **Hidden** — surrogate/identity primary keys (meaningless to an end user), audit-only timestamps
  that aren't central to triage (e.g. a "processed on" date when the row's current status already
  conveys that), and secondary/conditional fields that are only populated or relevant for a subset of
  rows (e.g. a rejection reason that's empty except when a row was rejected). These belong on the form,
  not the grid.
- **Read-only** — foreign-key/look-up columns and status-style columns whose value is meant to change
  only through a task/control procedure rather than a direct grid edit (see "Status columns" below for
  the same read-only default applied to the underlying column itself). Still shown, just not
  inline-editable from the grid.
  - **Carve-out**: on a weak entity's own detail tab, the FK column(s) that form the *inherited*
    part of its primary key (e.g. `customer_id` on `customer_address`, per "Column order" above)
    default to **Hidden** instead, not just read-only — its value is already implied by which parent
    row the detail is scoped under, so showing it as a read-only column adds nothing. Only show it
    (read-only or editable) if the user specifically asks for it, e.g. because the table is also
    browsed unscoped, outside its normal parent-filtered context. **Apply this on all three fields —
    `type_of_col`, `grid_type_of_col`, and `form_type_of_col`** — unlike the general "form defaults
    to visible/editable regardless of the grid" independence described below, this specific column
    is redundant everywhere for the same reason, so set all three to hidden together rather than
    only the grid.
- **Editable/visible** (the default) — reserve this for the columns that actually answer "what is this
  row, and what state is it in" at a glance: a handful of core identifying columns, the table's primary
  business figure (an amount, a quantity), and its key status. If a table's column count means most
  columns end up hidden or read-only, that's expected — a wide table rarely needs a wide grid.

This is a deliberate per-table design pass, the same as grouping/sort/search/filter above — decide it
once when the table's columns are created rather than leaving every column at its default and
revisiting later.

**Grid visibility is independent of form visibility — deciding one says nothing about the other.**
`grid_type_of_col` only controls the grid; `form_type_of_col` defaults to visible/editable regardless
of what the grid is set to. The platform's default detail screen still shows a record's form even when
the table's entire grid is read-only or task-driven (e.g. a history table where every write goes
through a task) — so a table designed to have "nothing editable" can still show every column, including
surrogate/identity ones, on the form. Before locking down a table's grid, separately decide (or ask the
user) whether the table's form should be visible at all, and size its column grouping (see "Form & grid
groups" below) against what the *form* actually shows, not against the grid.

**Views invert this default.** Everything above is written for a table, where columns start
editable and you lock a few down. A view stores nothing, so an editable column is inert
unless the view has an update handler or process logic that persists the edit — default
**every** view column to `read_only` (or `hidden` for surrogate keys and columns that only
exist to back the query or a reference), on all three of `type_of_col`/`grid_type_of_col`/
`form_type_of_col`, and make a column `editable` only where a user or the view's handler
genuinely writes it. `mand` follows the same line: it is only meaningful on an editable view
column, so default view columns to `mand = false` and set `mand = true` only where the column
is both editable and required. Full detail in `thinkwise_sf_views`'s
"Column editability and mandatory" section.

## Form & grid groups

Columns can be visually grouped on the form and, independently, in the grid header. Verified live
against the Software Factory's own meta-model (`col`, hundreds of tables): this is a consistently
applied convention, not an occasional nicety, and it should be **planned at the same time as column
order — before any column is created** (see "Decide the group plan up front" below), not bolted on
afterward.

This is about visually banding *columns* under a shared header, on the form and/or the grid. It's a
different mechanism from grouping grid *rows* into a collapsible tree by column value — see "Grid
row grouping and aggregation" below for that.

**Mechanism** — two independent pairs of fields on `col` (the same pattern exists on `task_parmtr`
for task forms, see `thinkwise_sf_tasks`):

| Context | "starts a new group" flag | Group label | Section-break variant |
|---|---|---|---|
| Form | `form_field_in_next_grp` (bool) | `form_next_grp_label` (string) | `field_on_next_tab` + `next_tab_label` — pushes onto a whole new tab, not just a new heading |
| Grid header | `grid_field_in_next_grp` (bool) | `grid_next_grp_label` (string) | — (grids have no tab concept) |

The flag and label are set **on the column that starts the new group** — not on the column that ends
the previous one. Form and grid grouping are independent: a grid can group columns differently than
the form, though in practice most tables just group the form and leave the grid ungrouped.

**Switching a column between the group and section-break variant needs two writes, not one.** The
two mechanisms are mutually exclusive on a given column, and turning `form_field_in_next_grp` off
also flips `form_next_grp_label` to a non-editable/hidden state — if the same write also tries to
clear that label (e.g. set it to null) or set `field_on_next_tab`/`next_tab_label` in one combined
call, the label write can be rejected because the field became non-editable partway through applying
that same call. Clear the old mechanism's flag first (as its own write), then set the new mechanism's
flag and label in a second write, rather than attempting the swap in one call.

**When to use them**: any table beyond a handful of columns, or with visually distinct concerns
(identity vs. status vs. settings vs. description) — group them. Don't group a table with only 2-3
closely related columns; there's nothing for a heading to separate.

**Which columns to bundle together**:
- First group holds the identifying/core descriptive columns (conventionally labeled `general`).
- One group per cohesive concern after that (`status`, `settings`, `description`, `positioning`,
  `authentication`, …) — never fold unrelated concerns into one group just to reduce group count.
- If the table has trace/audit columns (only when the user actually asked for them — see "Don't add
  trace/audit columns on your own initiative" under "Integrity, structure, and consistency"), the
  standing convention is a trailing group labeled `mutation`, additionally flagged
  `field_on_next_tab=true, next_tab_label="trace"` so the audit columns live on their own tab instead
  of cluttering the main form — this holds regardless of the table's subject matter.

**Naming**: lowercase snake_case, 1-3 words, a topic noun (`status`, not `"Status info"` or
`"status_columns"`). **Reuse an existing label instead of inventing a new one whenever the meaning
matches** — the real model reuses a small vocabulary of maybe 20-30 labels across hundreds of tables
(`general`, `description`, `status`, `settings`, `progress`, `positioning`, `assignment`, `tag`,
`generation`, `mutation`, `authentication`, `user_interface`, `condition`, `query`, `filter`,
`default_value`, …). This isn't just tidiness — see Translation below for why it's the whole point.

**Translation**: a group label's text is its own `transl_object_transl` row, keyed by the **literal
label string**, not by table+column: the label `general` has exactly one translation
row per language, shared and reused by every table that uses that label, already approved in ~17
languages. Reusing an existing label costs zero additional translation work. Inventing a new
spelling/casing variant (`"Status"` vs `"status"` vs `"state"`) creates a brand-new untranslated
object that has to go through the whole translation/approval cycle for no modeling benefit. After
introducing a genuinely new label, follow `thinkwise_sf_translations` to fill
in and approve it — the same standing requirement as any other new translatable object (see
"Translating new objects" above).

### Keep the group plan current when the table changes later

The "decide up front" rule above covers a brand-new table's first Form. The same discipline applies
afterward:

- **Adding a Form to a table for the first time, after the table already has columns** — treat it
  exactly like new-table design: decide the full group/section plan in one pass before setting any
  group flags, not incrementally per column.
- **Adding a single new column to a table whose Form already has groups/sections** — don't append
  the new column ungrouped at the end by default. Match it to whichever existing group covers the
  same concept, setting its order/group flags in the same write that creates the column. If no
  existing group is an obvious semantic fit, ask the user which group it belongs in (or whether it
  needs a new one) — see `thinkwise_sf_base`'s "Ask, don't default" rule — rather
  than guessing.
- **Retrofitting groups onto a table that already has ungrouped columns** — check the *first* visible
  column too, not just the ones after the first existing group starts. It's easy to group everything
  from the first semantic boundary onward and leave the leading identity/PK column(s) stranded outside
  any group simply because nothing preceded them to trigger the check.

## Sort, search, and filter

Every column has independent per-column settings for the table's default sort, its participation in
find/search, and its participation in the filter panel on `col`:
`default_sort`/`sort_no`/`sort_order`/`allow_sort` (sort), `visible_for_search`/`search_order_no`/
`search_condition`/`include_in_global_filter` (search/find), and `visible_for_filter`/
`filter_order_no`/`filter_condition` (filter). `visible_for_search` and `visible_for_filter` share
the same three-way enum: `always` / `extended` / `never`.

### Sort

**Every table should have a default sort set on the most sensible column(s)** — e.g. a natural
ordering column (`order_no`), a name/code, or a date (often descending, for "most recent first").
Set `default_sort=true` on each column that participates, `sort_no` to control precedence when more
than one column is involved (a composite sort), and `sort_order` (`asc`/`desc`) per column. Leave
`allow_sort=true` (the default) on any column a user could reasonably want to sort by; only turn it
off for columns where sorting is meaningless (large text/blob columns — see below).

**When the sensible default sort isn't obvious, ask the user rather than guessing** — unlike filter
and search below, this isn't a "safe default, override later" setting: a wrong default sort is
visible on every screen open and is a judgment call about the business data, not a mechanical rule.

### Search (find)

**A subject (strong entity, or the parent side of an inheritance relationship — see "Tables" above)
should always have search configured if its screen type has a grid.** Don't leave `visible_for_search`
at its unconfigured default (which behaves as `always` on every column) or skip search setup entirely
— deliberately choose `always`/`extended`/`never` per column following the guidance below, the same
required-follow-up treatment as translations and menu placement get elsewhere in this skill.

**Restrict `visible_for_search=always` to the table's genuinely important columns** — the ones a
user would actually type into a quick-find box to locate a row (names, codes, key statuses). Set
`visible_for_search=never` on any column backed by a large-object type — `NVARCHAR(MAX)`/
`VARCHAR(MAX)`, `VARBINARY(MAX)`/`IMAGE`, `TEXT`/`NTEXT`, `XML` (see "Data type recommendations"
above) — searching these is either meaningless (binary) or expensive (unbounded text) and never
what a quick-find is for. Default every other column to `extended` (available under advanced
find/search, not cluttering the default quick-search) rather than `always` — mirroring the filter
default below. Set `search_order_no` for a sensible position among the columns that do participate,
and `search_condition` to the operator that makes sense for the column's data (`contains` for free
text, `equal_to` for codes/numbers/domain-element-backed columns).

**`visible_for_search`/`search_condition`/`search_order_no` alone don't make a column searchable —
`include_in_global_filter` (a separate boolean, "Include in search") is the flag that actually puts
the column into the searchable set.** Set `include_in_global_filter=true` on every column that gets
`always` or `extended`, alongside its `visible_for_search`/`search_condition`/`search_order_no` —
missing this step leaves the column configured but silently excluded from search, with no error to
flag it.

### Filter

**Default every column's `visible_for_filter` to `extended`.** Only promote a column to `always`
when it's genuinely one of the most important columns on the screen *and* one of the filters a user
is actually likely to reach for often — treat `always` as the exception that has to earn its place,
not the default. As with search, large-object-typed columns (`NVARCHAR(MAX)`/`VARCHAR(MAX)`,
`VARBINARY(MAX)`/`IMAGE`, `TEXT`/`NTEXT`, `XML`) should be `never` rather than `extended` — they
can't be meaningfully filtered at all. Set `filter_order_no` to position the `always`/`extended`
columns sensibly, and `filter_condition` to the operator that fits the column (`contains` for free
text, `equal_to` for codes/domain-element-backed columns, `between` for ranges/dates).

**For the design reasoning behind these settings — which sort pattern fits which subject type, which
columns actually belong in search vs. filter, the deep-join/filter-form caution, tables-vs-views for
presentation reasons, and lookup-subject design — see
`references/subject_presentation_design.md`.** This section covers the fields; that file covers why
and which.
