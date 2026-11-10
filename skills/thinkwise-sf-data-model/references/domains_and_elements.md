# Domains, data types, domain elements, and status columns

Loaded on demand from `thinkwise-sf-data-model`.

## Domains
- **No data type (DTTP) in the name** (exceptions: XML, date and image values, where the type is the concept itself — but never the bare reserved word: `date` is a reserved keyword, so qualify it, e.g. `calendar_date`; see the reserved-word rule in the main skill file).
- **No length specification in the name** — a domain named `code_10` becomes wrong the moment the length changes.
- **No other meta-information** — describe the *business concept* (`email_address`, `currency_code`) so the domain can be reused consistently, not its implementation.
- Design for reuse: if two columns represent the same kind of value, they should share a domain rather than each defining an inline type.
- **Give email address, phone number, and web address domains their matching control**: `EMAIL`, `PHONE_NUMBER`, `URL` (`dom.control_id`; these control ids are global, not per model). Send `control_id` after `dttp_id` in the same write.
- **Never create/use a bare `id` domain for a primary/foreign key.** A generic `id` domain is exactly the kind of meta-information/no-context name this section rules out elsewhere — it doesn't say what it identifies, and it also invites collisions/reuse across unrelated keys that happen to share a data type. Name the domain after the specific entity it identifies, matching the column name it backs: domain `employee_id` for `employee.employee_id`, domain `sales_order_line_id` for `sales_order_line.sales_order_line_id` — not a shared `id` domain. Wrong: domain `id` used for both `employee.employee_id` and `sales_order_line.sales_order_line_id`. Right: separate `employee_id` and `sales_order_line_id` domains, one per entity. **Exception**: if the model being expanded already shares one generic `id`-style domain across essentially every table's surrogate key, see "When a guideline conflicts with an existing model's own established convention" above before introducing a new per-entity convention only for the objects you're adding.
- **This exact-match convention breaks on PostgreSQL via the Software Factory's own generation validation**: "PostgreSQL cannot have the same name for different objects within the same schema" — a domain and the column it backs cannot share an identical identifier on a Postgres branch, which the naming rule above produces by design (domain `employee_id` backing column `employee.employee_id` is exactly a same-name collision). This isn't limited to ID domains — any domain deliberately named identically to its column collides the same way (a live case: domains `address_type`/`address_line`/`postal_code` matching columns of the same name).
  **Check the branch's `rdbms_type` (see "Data type recommendations" below) before creating any domain. On a PostgreSQL branch, prefix every domain you create with `dom_`** (`employee_id` → `dom_employee_id`, and just as much for a non-ID domain like `email_address` → `dom_email_address`, even though that one wouldn't collide) — a blanket prefix applied to every domain, not a case-by-case check for whether *this* domain's name happens to match a column. Checking column-by-column doesn't scale (it's easy to catch it for one obvious ID domain and still miss it for an ordinary descriptive one) and produces a model where some domains are prefixed and others aren't for reasons no one remembers later. If expanding a model that already has a pre-existing, unprefixed domain, rename it too for consistency (via the dedicated rename task below) rather than leaving the model half-migrated.
  Use the dedicated rename task, not delete-and-recreate, and re-run the branch-wide placeholder-translation query afterward as usual — domains themselves don't carry their own `transl_object`, so this is normally a no-op, but confirm rather than assume.
- **Adding domains and elements (Indicium MCP)**: add `dom` as a dependent record under `branch`, then
  each `elemnt` under its `dom` (stage → patch → commit). On the current meta-model (SF 2026.2) `dom`
  has no `prog_lang_id` (`unknown_property`); the data type is `dttp_id`. On the legacy
  sf-mcp-server connector see `thinkwise-sf-create-domains` instead.
- **Field-naming trap when querying/scripting domains via metadata**: the entity itself is `dom`, and a
  column's foreign key to it is `dom_id` — not `domain_id`, despite "domain" being the natural English
  word for the concept. There is also no single `type_of_domain`-style field on `dom` — its data type
  lives in `dttp_id`/`dttp`, and its UI control in `control_id`. Confirm exact field names via the
  entity's own live metadata before guessing either one; both wrong guesses fail with the same
  "column could not be found"-style error.
- **Same naming trap for domain elements**: the rows themselves live on an entity set named
  `elemnt`, not `dom_elemnt` — even though `dom_elemnt` exists as its own distinct object-type
  identifier elsewhere in the metadata, which makes it a plausible but wrong guess. Confirm via
  `dom`'s own navigation properties (the one pointing at domain elements targets entity set
  `elemnt`) rather than assuming the name that "reads" correctly.

**API quirk**: a column's `mand` (mandatory) flag can revert to its domain's own default `mand` after the domain is assigned, even if the column's own `mand` override was set in the same or an immediately following write. This showed up on view columns that needed to be nullable (e.g. an optional end date) despite their domain defaulting to mandatory. Don't assume a combined "assign domain + set mand" write holds — after assigning a domain to a column that needs a different mandatory setting than the domain's default, re-read the column back and re-apply `mand` if it didn't take.

### Upload domains (images and files)

An upload is **two columns**, each on its own domain:
- **The file-name column** — a text domain (`VARCHAR`/`NVARCHAR` 255) with control `IMAGE_UPLOAD` or
  `FILE_UPLOAD` and a `file_storage_id`. Its `col.data_col_id` names the storage column; that field
  becomes mandatory once the domain has the upload control, so set it in the column's create write.
- **The storage column** — a binary `_MAX` domain (`VARBINARY(MAX)` on SQL Server, `BYTEA` on
  PostgreSQL) **without** a control. Hide it on the grid, form, and card list (`type_of_col`,
  `grid_type_of_col`, `form_type_of_col`, `card_list_type_of_col` hidden).

**Never put the upload control on the binary domain** — the Software Factory then requires a storage
column for every column of that domain. `dom.file_storage_id` is editable, and mandatory, only while an
upload control is set: send `control_id` first, then `file_storage_id`; to remove the control, clear
`file_storage_id` first, then `control_id`. Every file storage needs
`file_storage_extension_whitelist` rows, one per allowed extension, stored with the dot (`.png`, not
`png`) — an empty whitelist is flagged by `val_file_extension_whitelist_empty`.

## Data type recommendations

**These recommendations assume a SQL Server target — check the branch's actual RDBMS before applying
them.** A branch's RDBMS is set on `branch_rdbms_type`; query `dttp` filtered by that same
`rdbms_type` to see the actual set of types available on this branch before picking one — don't
assume a type mentioned below exists. **Verified live on a PostgreSQL branch: there is no
`NVARCHAR` and no `TINYINT` at all** — use `VARCHAR` (PostgreSQL has no fixed/variable Unicode
distinction, so plain `VARCHAR` is the sensible choice) and `SMALLINT` (the smallest available
integer type there) respectively wherever the guidance below says `NVARCHAR`/`TINYINT`. Other
non-SQL-Server platforms (Oracle, iSeries) likely have their own equivalent substitutions — verify
the same way rather than assuming.

- `DATETIME2` instead of `DATETIME`.
- `NVARCHAR` instead of `VARCHAR`, unless the character set must be restricted, in which case `VARCHAR` is acceptable.
- `NUMERIC` for decimals (avoid `FLOAT` due to rounding/precision issues).
- `INT`/`BIGINT` for identity columns.
- For booleans, use `BIT` (`1`/`0`) as the default choice; only use `CHAR`/`VARCHAR` (`'Y'`/`'N'`, `'T'`/`'F'`) if the business genuinely needs textual values.
- Avoid `CHAR`/`NCHAR` unless there's a specific justification (fixed-width values only).

## Domain elements
A **domain** is an abstract data type (Data > Domains) that standardizes the data type, constraints, and default UI control for every column/parameter using it. **Domain elements** are a fixed, pre-defined set of selectable values attached to a domain, used for `COMBO`, `IMAGE COMBO`, and `RADIO BUTTON` controls (e.g. a `payment_method` domain with elements `paypal`, `creditcard`, `prepaid`, `afterpay`).

**When to use domain elements vs. a lookup table** — straight from Thinkwise's SQL coding guidelines: **"Use a domain with domain elements if you need to program on values."**
- Use domain elements when control procedures / business logic need to branch, compare, or react to specific fixed values (e.g. `status = 'approved'`) — elements give each value a stable, named ID to reference in code instead of a magic string/number, with translation handled by the platform.
- Use a lookup/reference table instead when the value set is user-maintainable, expected to grow, needs additional attributes per value, or nobody writes code against specific values.
- Elements support being marked **inactive** (since 2021.2, per-variant since 2021.3) so old values keep working for historic data while hidden from new selections — a workaround for evolving a fixed set, not a substitute for a table when the set is inherently dynamic.

**Setting up and naming domain elements** (Data > Domains > Form):
- **Database value** — unless there's a specific reason to deviate (matching an external system's codes, or a value that must stay stable against an existing integration), use a **sequential integer starting at 0 or 1, incrementing by 1 per element**. Don't make the database value itself descriptive — that's what the ID is for.
- **ID** — the translatable label key shown to users; put all descriptive meaning here (e.g. `paypal`, `creditcard`, `prepaid`), decoupled from storage. An element's translation object is keyed by the element id alone, so every domain with an element `open`, `yes` or `new` shares one label. Give a generic id a distinguishing prefix (`order_status_open`) unless the shared label is genuinely wanted.
- **Sequence number** — controls display order in the combo/radio list independent of the database value.
- **Availability/active flag** — whether the element can still be newly selected.
- **Data type**: since the database value defaults to a small sequential integer, the preferred data type for a domain that uses elements is **TINYINT** rather than `INT`/`BIGINT` — no need to reserve more range than a handful of fixed options will ever use. Step up only if the database value deliberately isn't a small sequential integer (e.g. must match an external code exceeding 255, or is a bitmask).
- Grid vs. form can't natively show different translations for the same element (the workaround is a duplicated domain + expression field) — keep element ID translations reasonably concise so they work acceptably in both contexts.
- **When the domain's control is `IMAGE COMBO` or an icon-based `RADIO BUTTON`**, each element needs its own `elemnt.icon_id` — that's what actually renders instead of text. Follow `thinkwise-sf-icons`'s status-vocabulary guidance (unique silhouette per state, never color/icon alone) and its rule to ask the user rather than guess when no existing icon fits.
- **Setting `dom.control_id` to `IMAGE COMBO` (or another icon-capable control) silently resets `dom.alignment` to `right` for a numeric-typed domain** — even though a left-aligned icon/enum-style presentation is what an element-backed TINYINT domain normally wants. Confirmed live: 4 numeric domains all flipped to `alignment=1` right after their `control_id` was set, while sibling element-bearing domains that hadn't had `control_id` touched stayed at `alignment=0` left. Re-read `dom.alignment` immediately after any `control_id` write on a numeric domain and patch it back to `left` (pass the numeric value `0` — the string key `"left"` is rejected with `invalid_input`) unless the model's own convention is actually right-aligned for that domain type.
- **For a plain (non-icon) enum combo, no manual `control_id` write is needed at all.** Verified live across 7 TINYINT element domains: simply adding the `elemnt` rows auto-flipped `dom.control_id` to `COMBO`, and `dom.alignment` stayed `left` (`0`). So the workflow for a normal status/priority/proficiency domain is just: create the `dom` (TINYINT) → add its `elemnt` rows (`elemnt_id`, `db_value`, `order_no`, `available`) → done. The `control_id` write (and the alignment-reset fix above) only enters the picture when you deliberately want `IMAGE COMBO`/icon presentation.

## Status columns

**Unless the user states otherwise, a status column defaults to read-only, mandatory, with a default
value:**
- **Mandatory (`mand = true`)** — a row should never sit in a null/undefined status.
- **A default value set** (the column's own default, or a Default control procedure) so every new row
  gets a sensible initial status (e.g. `new`/`draft`) without the caller having to supply one.
- **Read-only on the form/grid** — don't let an end user free-edit the column directly; a status is a
  business state, not a plain data field. Keep it read-only unless users genuinely must edit it.
- **Never make a status read-only without a default** — with no default and no way to type a value,
  users cannot insert a row at all.

**Unless the user states otherwise, status changes are made by a task or control procedure, not by a
direct column edit.** Model one task per transition (e.g. `submit`/`approve`/`reject`) that performs
the update — see `thinkwise-sf-tasks` — so each transition can validate preconditions and trigger side
effects, rather than exposing the raw column for arbitrary overwrite. Give each such task a Context
procedure that disables it outside the statuses it may leave from (needs `use_contexts` on the table),
so a user only sees the transitions valid for the current row. A status backed by domain elements (see "Domain elements" above) is what
lets that task/control-procedure logic branch on a stable element ID instead of a magic value.
