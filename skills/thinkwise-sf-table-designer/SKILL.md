---
name: thinkwise-sf-table-designer
description: >
  Design Thinkwise Software Factory tables (domains, columns, primary keys, references) for the
  older Software Factory meta-model (dom.prog_lang_id, dom_elmnt, tab.work_flow_tab_id,
  col.case_type) and output them as SQL INSERT statements to run against the branch database, not
  as connector writes. ALWAYS trigger on the slash command /table. On the current meta-model
  (SF 2026.2, with elemnt and no dom.prog_lang_id) or when writing through an Indicium MCP connector,
  use thinkwise-sf-data-model instead.
---

# Thinkwise Table Designer

## Purpose
Generate a complete Thinkwise Software Factory table definition from natural language input, and the SQL `INSERT` statements that write it into an **older** Software Factory meta-model, including:
- Table name and description
- Domains (user-defined datatypes)
- Columns with data types, constraints, and domain assignments
- Primary key definition
- Foreign key columns and references (when multiple tables are involved)

**Scope `(older meta-model)`.** The output is SQL for the older meta-model field set (`dom.prog_lang_id`, `dom.user_defined_dttp`, `dom.allocate_length`, `dom_elmnt`, `tab.work_flow_tab_id`, `tab.priority`, `col.case_type`, …). On the current meta-model (SF 2026.2: elements in `elemnt`, the datatype set on `dom` and copied to `dom_query`, no `dom.prog_lang_id` or `col.case_type`), or when the design is written through an Indicium MCP connector, use `thinkwise-sf-data-model` instead.

**Conventions.** Where this skill's naming and type rules differ from `thinkwise-sf-data-model`, follow `thinkwise-sf-data-model`: `INT` identity for surrogate keys (`BIGINT` only for tables expected to exceed ~2 billion rows), column `order_no` in steps of 10 starting at 10, and no column or domain named after a SQL reserved word (`date`, `time`, `level`, `year`, `order`, `value`, … — check SQL Server and PostgreSQL).

---

## Step 0 — Check the meta-model

Before the wizard, confirm the target uses the older meta-model:

- **Connector or pasted metadata available** — check that `dom` has a `prog_lang_id` field, or that a `dom_elmnt` table exists (a `$top=1` sample of `dom`, or the pasted metadata).
- **Neither exists** — the target is the current meta-model. Stop and route to `thinkwise-sf-data-model`; don't generate INSERTs.
- **Can't be determined** (no connector, no metadata) — ask the user which Software Factory version they're on before continuing.

---

## Step 1 — Wizard: collect input via interactive questions

Collect input with the structured question tool — `ask_user_input_v0` in claude.ai/ThinkIT, `AskUserQuestion` in Claude Code — or, without either, plain-text questions. Follow this exact two-round sequence:

### Round 1 — Entity and FK links (one tool call, two questions)

- **Q1 (single_select):** "What business entity or concept does this table represent?"
  Offer 4-5 common domain examples (e.g. Customer, Product, Order, Employee) plus "Something else..."
  If "Something else..." is chosen, follow up in plain text asking them to describe the entity.

- **Q2 (single_select):** "Are there existing tables this table should link to (via foreign keys)?"
  Options: "Yes, I'll describe them" / "No, this is a standalone table" / "Not sure yet"
  If "Yes", follow up in plain text asking for table names and their PK column names.

### Round 2 — Column selection (one tool call, one or two questions)

Once you know the entity, deduce a sensible set of columns based on general domain knowledge. Present them as a multi-select:

- **Q1 (multi_select):** "I'd suggest these columns for a {entity} table. Which ones do you want to include?"
  List 6-10 logically deduced columns with short labels (e.g. "title (required)", "release_date", "genre", "is_active (flag)").
  The user selects which to keep and can type additional ones afterward.

- **Q2 (single_select, only if a categorical/list-like column is present such as genre, status, type):**
  "Should [column] be a fixed list of values or free text?"
  Options: "Fixed list (combo)" / "Free text"

Do NOT generate the table definition until both rounds are complete.

---

## Step 2 — Apply Thinkwise naming conventions

Before generating, apply these rules strictly:

### General naming
- All names **lowercase**, words separated by **underscores**
- **Singular** form for table names (e.g. `sales_order`, not `sales_orders`)
- No abbreviations (except `id`, `nr`, `no`)
- No meta information in names (no `tbl_`, `dttp_`, lengths, etc.)
- Names must be **self-explanatory**

### Primary keys
- Strong entity: **1 PK column**, named `{table_name}_id` (e.g. `sales_order_id`)
- PK data type: **INT IDENTITY** — use `BIGINT IDENTITY` only for tables expected to exceed ~2 billion rows
- Weak entity (e.g. order line): **composite PK** — all FK columns of the parent(s) first, then the own `{table_name}_id` last
  - The last PK column is NOT a foreign key; the others are
  - Weak entity has exactly one more PK column than its parent
  - Weak entity name = parent name + addition (e.g. `sales_order_line`)

### Foreign keys
- FK column has the **same name as the PK of the parent table** (e.g. if parent PK is `customer_id`, FK is also `customer_id`)
- If a table references the same parent twice, prefix the FK with a qualifier (e.g. `origin_sales_order_id`, `destination_sales_order_id`)
- Each FK column gets its **own reference** (1 FK column = 1 reference)
- Database check must be enabled on every reference

### Link tables (many-to-many)
- PK = all PK columns from both source tables (all are also FK)
- Name = combination of both table names (e.g. `employee_project`)

### Recursive relations
- The self-referencing FK gets a **new, descriptive name** (not derived), e.g. `parent_category_id`

---

## Step 3 — Define domains

Each column must be assigned a domain. Apply these rules:

- **No** `DTTP` prefix in domain name
- **No** length in domain name (not `name_50`, but `name`)
- **No** meta information
- PK columns that are not FK columns: domain name = column name (e.g. column `sales_order_id` → domain `sales_order_id`)
- Reuse existing domains when the user has indicated they already exist
- **Entity-specific naming for descriptive domains:** domains like `name`, `description`, `code` must be prefixed with the entity they belong to. Examples:
  - `article_name`, `customer_name`, `employee_name` — NOT a generic `name`
  - `article_description`, `order_description` — NOT a generic `description`
  - `article_code`, `product_code` — NOT a generic `code`
  - This allows each entity to have different length, casing, or validation requirements
  - **Reuse rule:** if a column in table B refers to the same concept as an existing domain from table A (e.g. `article_description` already exists and table B also needs an article description), reuse that domain — do NOT create a new one
- **Truly generic domains** are allowed only for data types that carry no entity-specific meaning:
  - `amount` — NUMERIC(18,2), monetary/decimal values
  - `quantity` — NUMERIC(18,4)
  - `date_time` — DATETIME2
  - a DATE domain named after its concept (e.g. `start_date`) — never bare `date`, a reserved word
  - `flag` — BIT, for boolean yes/no columns
  - `remark` — NVARCHAR(MAX), for free-form notes (generic enough across entities)
  - Identity PK domains: INT IDENTITY, named after the column (e.g. `sales_order_id`)

**Data type preferences (SQL Server):**
- Text: `NVARCHAR(n)` unless charset restriction needed → then `VARCHAR(n)`
- Long text: `NVARCHAR(MAX)`
- Integers (non-identity): `INT` or `BIGINT`
- Identity PK: `INT IDENTITY` (`BIGINT IDENTITY` only for tables expected to exceed ~2 billion rows)
- Decimal/money: `NUMERIC(p, s)`
- Date+time: `DATETIME2` (never `DATETIME`)
- Date only: `DATE`
- Boolean: `BIT`

---

## Step 4 — Output format

Produce a clearly formatted table definition using this structure:

```
## Table: {table_name}
**Description:** {what this table stores}
**Entity type:** Strong / Weak / Link

### Domains (new)
| Domain name       | Data type       | Length | Scale | Min | Max | Elements | Notes           |
|-------------------|-----------------|--------|-------|-----|-----|----------|-----------------|
| sales_order_id    | INT IDENTITY    |        |       |     |     |          | PK identity     |
| ...               | ...             |        |       |     |     |          |                 |

### Domains (reuse existing)
List any domains from existing tables that should be reused (e.g. FK domains).

### Columns
| order_no | Column name       | Domain            | PK | FK | Mandatory | Notes                        |
|---|-------------------|-------------------|----|----|-----------|------------------------------|
| 10 | sales_order_id    | sales_order_id    | ✓  |    | ✓         | Identity PK                  |
| 20 | customer_id       | customer_id       |    | ✓  | ✓         | FK → customer.customer_id    |
| 30 | order_date        | date_time         |    |    | ✓         |                              |
| 40 | description       | sales_order_description |    |    |           |                              |

### References
| Reference name          | From (FK column)  | To table   | To column (PK) | DB check |
|-------------------------|-------------------|------------|----------------|----------|
| ref_customer_sales_order | customer_id      | customer   | customer_id    | ✓        |
```

If multiple tables are needed, repeat the block for each table and add a **Relationship overview** section summarizing all FK links.

---

## Step 5 — Confirm and iterate

After generating the definition, ask:
- "Does this match what you had in mind? Should I adjust any column names, types, or relationships?"
- Offer to add extra columns, change entity type, or split/merge tables if the design seems off.

---

## Step 6 — Generate SF meta-model INSERT statements

After confirming the table design, generate ready-to-run `INSERT` statements for the Thinkwise Software Factory meta-model. Ask the user for two values needed as context:

- `@model_id` — the SF model ID (e.g. `MyApp`)
- `@branch_id` — the branch ID (e.g. `trunk`)

Then generate INSERT statements for each meta-model table in this order: `dom` → `dom_elmnt` → `tab` → `col` → `ref` → `ref_col`.

### Rules for generating INSERTs

**General:**
- Always include `model_id` and `branch_id` using the values provided.
- Omit all audit/system columns: `insert_user`, `insert_date_time`, `update_user`, `update_date_time`, `generated_by_control_proc_id`, `tsf_valid_from`, `tsf_valid_to`.
- Use `NULL` for nullable columns that have no meaningful value to set.
- Use single quotes for string values. Escape single quotes by doubling them.
- Add a comment header above each block: `-- DOM`, `-- TAB`, `-- COL`, `-- REF`, `-- REF_COL`.

---

### `dom` — one row per new domain

Only generate rows for domains that are **new** (not reused from existing tables). A domain is reusable when:
- It is an FK domain (e.g. `customer_id` already exists on the `customer` table — reuse it)
- It is an entity-specific domain that was already created for another table (e.g. `article_description` defined when designing `article` — reuse it when another table also needs an article description)

Do NOT reuse generic names like `description`, `name`, or `code` — these must always be entity-prefixed (e.g. `article_description`, `customer_name`). Truly generic reusable domains are limited to: `amount`, `quantity`, `date_time`, `flag`, `remark` (a date domain is named after its concept, never bare `date`).

Key columns to set:
| Column | Value |
|---|---|
| `model_id` | `@model_id` |
| `branch_id` | `@branch_id` |
| `dom_id` | domain name (e.g. `sales_order_id`) |
| `prog_lang_id` | always `'sql'` |
| `dttp_id` | SQL Server type ID — see mapping below |
| `length` | length for VARCHAR/NVARCHAR; precision (total digits) for NUMERIC; else `NULL` |
| `prec` | scale (number of decimals) for NUMERIC — `NUMERIC(p,s)` is `length` p, `prec` s; else `NULL` |
| `mand` | `'0'` (not mandatory at domain level by default) |
| `alignment` | `0` (left) for text, `1` (right) for numeric — left 0, right 1, center 2; the Software Factory sets 1 for a numeric type itself |
| `sort_order_elemnt` | `0` |
| `type_of_default_value` | `0` (no default) |
| `case_type` | `0` |
| `show_action_button` | `0` |
| `show_local_time` | `0` |
| `no_of_elemnt` | `0` |
| `read_only_input_control` | `'0'` |
| `word_wrap` | `'0'` |
| `default_include_in_global_filter` | `'0'` |
| `default_visible_for_filter` | `0` |
| `default_visible_for_search` | `0` |
| `use_for_optimistic_locking` | `'0'` |

**`dttp_id` mapping (SQL Server type → SF dttp_id):**
| SQL type | dttp_id |
|---|---|
| NVARCHAR | `nvarchar` |
| VARCHAR | `varchar` |
| NVARCHAR(MAX) | `nvarchar` (length = -1) |
| BIGINT IDENTITY | `bigint` |
| BIGINT | `bigint` |
| INT | `int` |
| NUMERIC | `numeric` |
| DATETIME2 | `datetime2` |
| DATE | `date` |
| BIT | `bit` |

---

### `dom_elmnt` — one row per element, for every domain that is a fixed list (combo)

When the user has chosen "Fixed list (combo)" for a column, ask for the element values before generating. Each element becomes one row in `dom_elmnt`. If the user hasn't provided values yet, ask: *"What values should the fixed list for `{dom_id}` contain? Please provide them as a comma-separated list, e.g. `Draft, Confirmed, Shipped, Cancelled`."*

The `db_value` is a short, system-safe version of the element — lowercase, no spaces, max 25 chars (e.g. `draft`, `confirmed`) — and is always written as a string, also for a numeric domain (`'1'`). The `elemnt_id` is a lowercase snake_case id (e.g. `draft`, `confirmed`) and is the translation key: the label users see is a `transl_object_transl` row of type 2 keyed by the bare `elemnt_id`, so equal element ids in different domains share one label. Give a generic id (`open`, `yes`, `active`, `new`) a distinguishing prefix (`order_status_open`) unless sharing that label across the model is intended. A column default on an element domain is the element's `db_value`, not its id or position.

Key columns to set:
| Column | Value |
|---|---|
| `model_id` | `@model_id` |
| `branch_id` | `@branch_id` |
| `dom_id` | domain name (e.g. `order_status`) |
| `elemnt_id` | snake_case id, also the translation key (e.g. `draft`) |
| `db_value` | short system value, max 25 chars (e.g. `draft`) |
| `icon_id` | `NULL` |
| `order_no` | sequential starting at 1 |
| `abs_order_no` | same as `order_no` |
| `available` | `'1'` |

---

### `tab` — one row per table

Key columns to set:
| Column | Value |
|---|---|
| `model_id` | `@model_id` |
| `branch_id` | `@branch_id` |
| `tab_id` | table name |
| `type_of_table` | `0` (normal table) |
| `create_view_method` | `0` |
| `default_look_up_control` | `0` |
| `default_refresh_combo_on_dropdown` | `'0'` |
| `default_look_up_has_popup` | `'0'` |
| `form_default_editable` | `'1'` |
| `form_auto_save` | `'0'` |
| `hide_buttons` | `'0'` |
| `allow_add` | `'1'` |
| `allow_copy` | `'1'` — with `allow_add` `'0'` the Software Factory sets `allow_copy` `'0'` itself and locks it; never send `allow_copy` alone |
| `allow_update` | `'1'` |
| `allow_delete` | `'1'` |
| `allow_copy_to_clipboard` | `'1'` |
| `confirm_update` | `'0'` |
| `confirm_delete` | `'1'` |
| `refresh_after_insert` | `0` |
| `refresh_after_copy` | `0` |
| `refresh_after_update` | `0` |
| `refresh_after_delete` | `0` |
| `start_empty_with_filter` | `'0'` |
| `allow_nav` | `'1'` |
| `allow_sort` | `'1'` |
| `allow_grp` | `'1'` |
| `allow_filter` | `'1'` |
| `allow_search` | `'1'` |
| `allow_edit_grid` | `'1'` |
| `allow_add_grid` | `'0'` |
| `add_row_visibility` | `0` |
| `allow_import` | `'0'` |
| `allow_export` | `'1'` |
| `allow_mass_update` | `'0'` |
| `grid_default_editable` | `'0'` |
| `auto_resize_grid_col` | `0` |
| `grp_grid_default_expanded` | `'1'` |
| `allow_print_preview` | `'0'` |
| `drag_drop_default_enabled` | `'0'` |
| `grp_box_visibility` | `0` |
| `update_trigger_on_cols` | `'0'` |
| `height_unit_type` | `0` |
| `memory_optimized` | `0` |
| `use_system_versioning` | `'0'` |
| `system_versioning_retention_unit` | `0` |
| `type_of_object` | `0` |
| `visible_in_uml` | `'1'` |
| `priority` | `0` |
| `show_no_of_record` | `'0'` |
| `card_list_title` | `0` |
| `card_list_image` | `0` |
| `tree_type` | `0` |
| `tree_default_expanded` | `'0'` |
| `tree_show_label` | `'0'` |
| `no_of_col` | number of columns in table |
| `no_of_pk_col` | number of PK columns |
| `max_pk_col_no` | order_no of last PK column |
| `allow_offline` | `'0'` |
| `offline_available` | `'0'` |
| `offline_mutable` | `'0'` |
| `refresh_offline_data_after_mutation` | `'0'` |
| `use_defaults` | `'1'` |
| `use_layouts` | `'0'` |
| `use_layouts_add_button_type` | `'0'` |
| `use_layouts_update_button_type` | `'0'` |
| `use_layouts_delete_button_type` | `'0'` |
| `use_layouts_confirm_button_type` | `'0'` |
| `use_layouts_cancel_button_type` | `'0'` |
| `use_contexts` | `'0'` |
| `use_badges` | `'0'` |
| `show_badge` | `'0'` |
| `use_change_detection` | `'0'` |
| `use_insert_handlers` | `'0'` |
| `use_update_handlers` | `'0'` |
| `use_delete_handlers` | `'0'` |
| `auto_refresh` | `'0'` |
| `use_insert_handlers_template` | `'0'` |
| `use_update_handlers_template` | `'0'` |
| `use_delete_handlers_template` | `'0'` |
| `enable_multirow_select` | `'0'` |
| `tab_description` | table description as string, or `NULL` |

---

### `col` — one row per column, ordered by `order_no`

Assign `order_no` starting at 10, incrementing by 10. PK columns come first in the same order as defined.

Key columns to set:
| Column | Value |
|---|---|
| `model_id` | `@model_id` |
| `branch_id` | `@branch_id` |
| `tab_id` | table name |
| `col_id` | column name |
| `order_no` | 10, 20, 30, … |
| `sub_order_no` | same as `order_no` |
| `abs_order_no` | same as `order_no` |
| `dom_id` | domain name assigned to this column |
| `primary_key` | `'1'` if PK, else `'0'` |
| `type_of_col` | `0` (editable) |
| `mand` | `'1'` if mandatory, else `'0'` |
| `type_of_default_value` | `0` (no default), or `1` if identity |
| `foreign_key` | `'1'` if FK, else `'0'` |
| `identity_col` | `'1'` if IDENTITY, else `'0'` |
| `seed` | `1` for identity columns, else `NULL` |
| `increment` | `1` for identity columns, else `NULL` |
| `default_sort` | `'0'` |
| `grp_until` | `'0'` |
| `field_no_of_positions_further` | `0` |
| `form_field_in_next_grp` | `'0'` |
| `field_in_next_col` | `'0'` |
| `field_on_next_tab` | `'0'` |
| `next_tab_default_expanded` | `'0'` |
| `grid_field_in_next_grp` | `'0'` |
| `case_type` | `0` |
| `include_in_insert` | `'1'` (except identity cols: `'0'`) |
| `include_in_copy` | `'1'` (except identity cols and non-key columns of a unique index: `'0'`, otherwise a copy breaks the index) |
| `include_in_copy_to_clipboard` | `'1'` |
| `allow_sort` | `'1'` |
| `include_in_global_filter` | `'0'` |
| `visible_for_filter` | `0` |
| `filter_order_no` | `0` |
| `visible_for_search` | `0` |
| `search_order_no` | `0` |
| `trigger_for_update` | `'0'` |
| `type_of_object` | `0` |
| `form_order_no` | same as `order_no` |
| `grid_order_no` | same as `order_no` |
| `show_aggregation_in_grid` | `'0'` |
| `calculated_field_type` | `0` |
| `file_offline_available` | `'0'` |
| `default_input` | `'1'` |
| `default_output` | `'1'` |
| `layout_input` | `'0'` |
| `layout_type_output` | `'0'` |
| `layout_mand_output` | `'0'` |
| `context_input` | `'0'` |
| `function_input` | `'0'` |
| `use_for_optimistic_locking` | `'0'` |
| `input_insert_handler` | `'0'` |
| `input_update_handler` | `'0'` |
| `has_alt_transl` | `'0'` |
| `col_description` | column description, or `NULL` |

---

### `ref` — one row per reference

The **source** of a reference is the parent table whose primary key is referenced; the **target** is the child table that holds the foreign key. The `ref_id` is constructed as: `ref_{source_tab_id}_{target_tab_id}` (e.g. `ref_customer_sales_order`). If a table has multiple references to the same target, append a qualifier through `ref_add` (`ref_{source_tab_id}_{target_tab_id}_{ref_add}`, e.g. `ref_customer_sales_order_origin`).

**`(Indicium MCP)`** These INSERTs are not the connector route. When the design is written through an Indicium MCP connector, hand over to `thinkwise-sf-data-model` ("References" → "Creating one"): a direct `ref` add under `branch` (send `source_tab_id`, then `target_tab_id`; `ref_id` is derived and read-only), then `ref_col` under `ref`. The alternative, `task_create_ref`, is bound to `ref`, not to `branch`; on it `source_col_id_n` is read-only, filled from the source table's key, and `new_col_n`/`target_col_id_n` exist only up to the number of key columns of the source. On both routes `on_update`/`on_delete` stay read-only unless `check_ref` is true, and `look_up_display_col_id` is editable only after `different_look_up` is true.

Key columns to set:
| Column | Value |
|---|---|
| `model_id` | `@model_id` |
| `branch_id` | `@branch_id` |
| `ref_id` | constructed ref name |
| `source_tab_id` | source (parent, PK) table name |
| `target_tab_id` | target (child, FK) table name |
| `check_ref` | `'1'` (always enable DB check) |
| `on_update` | `0` (no action) |
| `on_delete` | `0` (no action) |
| `no_of_col` | number of FK columns in this reference (usually 1) |
| `show_look_up` | `'1'` |
| `different_look_up` | `'0'` |
| `look_up_control` | `0` |
| `refresh_combo_on_dropdown` | `'0'` |
| `look_up_has_popup` | `'0'` |
| `show_detail` | `'0'` |
| `order_no` | sequential per source table, starting at 1 |
| `abs_order_no` | same as `order_no` |
| `is_detail` | `'0'` |
| `context_type_output` | `'0'` |
| `visible_for_filter_detail` | `0` |
| `visible_for_filter_look_up` | `0` |
| `generate_ref_add_transl_object` | `'0'` |

---

### `ref_col` — one row per FK column per reference

Key columns to set:
| Column | Value |
|---|---|
| `model_id` | `@model_id` |
| `branch_id` | `@branch_id` |
| `ref_id` | same `ref_id` as in `ref` |
| `source_tab_id` | PK (parent) table name |
| `source_col_id` | PK column name of the source table |
| `target_tab_id` | FK (child) table name |
| `target_col_id` | FK column name |
| `order_no` | `1` (or sequential if composite FK) |
| `abs_order_no` | same as `order_no` |
| `use_detail_null_comparison` | `'0'` |

---

### Output format

Present the SQL as a single fenced code block with `sql` syntax highlighting. Group by meta-table with comment headers. Example structure:

```sql
-- DOM
INSERT INTO dom (model_id, branch_id, dom_id, prog_lang_id, dttp_id, ...)
VALUES ('MyApp', 'trunk', 'sales_order_id', 'sql', 'int', ...);

-- DOM_ELMNT
INSERT INTO dom_elmnt (model_id, branch_id, dom_id, elemnt_id, db_value, order_no, abs_order_no, available)
VALUES ('MyApp', 'trunk', 'order_status', 'draft', 'draft', 1, 1, '1');

-- TAB
INSERT INTO tab (model_id, branch_id, tab_id, ...)
VALUES ('MyApp', 'trunk', 'sales_order', ...);

-- COL
INSERT INTO col (model_id, branch_id, tab_id, col_id, order_no, ...)
VALUES ('MyApp', 'trunk', 'sales_order', 'sales_order_id', 10, ...);
-- ... one row per column

-- REF
INSERT INTO ref (model_id, branch_id, ref_id, source_tab_id, target_tab_id, ...)
VALUES ('MyApp', 'trunk', 'ref_customer_sales_order', 'customer', 'sales_order', ...);

-- REF_COL
INSERT INTO ref_col (model_id, branch_id, ref_id, source_tab_id, source_col_id, target_tab_id, target_col_id, ...)
VALUES ('MyApp', 'trunk', 'ref_customer_sales_order', 'customer', 'customer_id', 'sales_order', 'customer_id', ...);
```

After presenting the SQL, remind the user: *"Run these statements against your SF branch database. Make sure the model and branch already exist before inserting."*

---

## Meta-model column reference

These are the exact column definitions for each SF meta-model table. Use them to construct complete, correctly-ordered INSERT statements. Audit columns (`insert_user`, `insert_date_time`, `update_user`, `update_date_time`, `generated_by_control_proc_id`, `tsf_valid_from`, `tsf_valid_to`) are always omitted from INSERTs.

### `dom`
| Column | Domain | Nullable |
|---|---|---|
| model_id | model_id | no |
| branch_id | branch_id | no |
| dom_id | dom_id | no |
| prog_lang_id | prog_lang_id | no |
| dttp_id | dttp_id | no |
| length | length | yes |
| prec | prec | yes |
| dttp | dttp | yes |
| user_defined_dttp | dttp | yes |
| allocate_length | length | yes |
| control_id | control_id | yes |
| show_local_time | show_local_time | no |
| min_value | min_value | yes |
| max_value | max_value | yes |
| mand | no_yes | no |
| alignment | alignment | no |
| sort_order_elemnt | sort_order_elemnt | no |
| type_of_default_value | type_of_default_value | no |
| default_value | default_value | yes |
| default_value_query | query | yes |
| case_type | case_type | no |
| field_width | width | yes |
| field_height_in_positions | no | yes |
| grid_col_width | width | yes |
| default_include_in_global_filter | no_yes | no |
| default_visible_for_filter | visible_for_filter_search | no |
| default_filter_condition | filter_condition | yes |
| default_visible_for_search | visible_for_filter_search | no |
| default_search_condition | filter_condition | yes |
| file_storage_id | file_storage_id | yes |
| html_control_font_id | font_id | yes |
| show_action_button | show_action_button | no |
| read_only_input_control | no_yes | no |
| word_wrap | no_yes | no |
| dom_description | description_multiline | yes |
| use_for_optimistic_locking | no_yes | no |
| no_of_elemnt | no_of_elemnt | no |

### `dom_elmnt`
| Column | Domain | Nullable |
|---|---|---|
| model_id | model_id | no |
| branch_id | branch_id | no |
| dom_id | dom_id | no |
| elemnt_id | elemnt_id | no |
| db_value | db_value | no |
| icon_id | icon_id | yes |
| order_no | order_no | no |
| abs_order_no | abs_order_no | no |
| available | no_yes | no |

### `tab`
| Column | Domain | Nullable |
|---|---|---|
| model_id | model_id | no |
| branch_id | branch_id | no |
| tab_id | tab_id | no |
| type_of_table | type_of_tab | no |
| create_view_method | create_view_method | no |
| main_screen_type_id | screen_type_id | yes |
| detail_screen_type_id | screen_type_id | yes |
| zoom_screen_type_id | screen_type_id | yes |
| popup_screen_type_id | screen_type_id | yes |
| look_up_display_col_id | col_id | yes |
| default_look_up_control | look_up_control | no |
| default_refresh_combo_on_dropdown | no_yes | no |
| default_look_up_has_popup | no_yes | no |
| form_default_editable | no_yes | no |
| form_auto_save | no_yes | no |
| hide_buttons | no_yes | no |
| allow_add | no_yes | no |
| allow_copy | no_yes | no |
| allow_update | no_yes | no |
| allow_delete | no_yes | no |
| allow_copy_to_clipboard | no_yes | no |
| confirm_update | no_yes | no |
| confirm_delete | no_yes | no |
| refresh_after_insert | refresh | no |
| refresh_after_copy | refresh | no |
| refresh_after_update | refresh | no |
| refresh_after_delete | refresh | no |
| start_empty_with_filter | no_yes | no |
| allow_nav | no_yes | no |
| allow_sort | no_yes | no |
| allow_grp | no_yes | no |
| allow_filter | no_yes | no |
| allow_search | no_yes | no |
| allow_edit_grid | no_yes | no |
| allow_add_grid | no_yes | no |
| add_row_visibility | add_row_visibility | no |
| allow_import | no_yes | no |
| allow_export | no_yes | no |
| allow_mass_update | no_yes | no |
| grid_row_height | height | yes |
| grid_default_editable | no_yes | no |
| auto_resize_grid_col | auto_resize_grid_col | no |
| grp_grid_default_expanded | no_yes | no |
| grp_grid_default_expanded_level | default_expanded_level | yes |
| allow_print_preview | no_yes | no |
| drag_drop_default_enabled | no_yes | no |
| grp_box_visibility | grp_box_visibility | no |
| update_trigger_on_cols | no_yes | no |
| height_unit_type | height_unit_type | no |
| default_height_main_subject | height | yes |
| work_flow_tab_id | tab_id | yes |
| view_schema_id | source_schema_id | yes |
| view_from_clause | source_from_clause | yes |
| view_where_clause | source_where_clause | yes |
| view_grp_by_clause | source_grp_by_clause | yes |
| view_having_clause | source_having_clause | yes |
| icon_id | icon_id | yes |
| max_no_of_records | no_of_records | yes |
| page_size | no_of_records | yes |
| no_of_fields_locked | no_of_col | yes |
| storage_id | storage_id | yes |
| alias_schema_id | alias_schema_id | yes |
| alias_tab_id | alias_tab_id | yes |
| memory_optimized | memory_optimized_option | no |
| use_system_versioning | no_yes | no |
| system_versioning_retention_amount | recurrence | yes |
| system_versioning_retention_unit | retention_type | no |
| partition_scheme_id | partition_scheme_id | yes |
| partition_col_id | col_id | yes |
| tab_description | description_multiline | yes |
| type_of_object | type_of_object | no |
| derived_concepts | derived_concepts | yes |
| visible_in_uml | no_yes | no |
| priority | priority | no |
| no_of_cols_in_form | no_of_col | yes |
| form_col_min_width_factor | form_col_min_width_factor | yes |
| label_width | width | yes |
| field_width | width | yes |
| field_height | height | yes |
| height_between_fields | height | yes |
| width_between_fields | width | yes |
| show_no_of_record | no_yes | no |
| card_list_title | card_list_title | no |
| card_list_image | card_list_image | no |
| tree_display_col_id | col_id | yes |
| tree_image_col_id | col_id | yes |
| tree_type | tree_type | no |
| tree_default_expanded | no_yes | no |
| tree_default_expanded_level | default_expanded_level | yes |
| tree_show_label | no_yes | no |
| custom_component_ref | custom_component_ref | yes |
| generation_order_no | order_no | yes |
| no_of_col | no_of_col | no |
| no_of_pk_col | no_of_pk_col | no |
| max_pk_col_no | max_pk_col_no | no |
| allow_offline | no_yes | no |
| offline_available | no_yes | no |
| offline_mutable | no_yes | no |
| refresh_offline_data_after_mutation | no_yes | no |
| refresh_grp_id | refresh_grp_id | yes |
| use_defaults | no_yes | no |
| use_layouts | no_yes | no |
| use_layouts_add_button_type | no_yes | no |
| use_layouts_update_button_type | no_yes | no |
| use_layouts_delete_button_type | no_yes | no |
| use_layouts_confirm_button_type | no_yes | no |
| use_layouts_cancel_button_type | no_yes | no |
| use_contexts | no_yes | no |
| use_badges | no_yes | no |
| show_badge | no_yes | no |
| badge_interval | badge_interval | yes |
| use_change_detection | no_yes | no |
| use_insert_handlers | no_yes | no |
| use_update_handlers | no_yes | no |
| use_delete_handlers | no_yes | no |
| auto_refresh | no_yes | no |
| auto_refresh_interval | auto_refresh_interval | yes |
| use_insert_handlers_template | no_yes | no |
| use_update_handlers_template | no_yes | no |
| use_delete_handlers_template | no_yes | no |
| enable_multirow_select | no_yes | no |

### `col`
| Column | Domain | Nullable |
|---|---|---|
| model_id | model_id | no |
| branch_id | branch_id | no |
| tab_id | tab_id | no |
| col_id | col_id | no |
| order_no | order_no | no |
| sub_order_no | sub_order_no | no |
| abs_order_no | abs_order_no | no |
| dom_id | dom_id | no |
| primary_key | no_yes | no |
| type_of_col | type_of_col | no |
| mand | no_yes | no |
| type_of_default_value | type_of_default_value | no |
| default_value | default_value | yes |
| default_value_query | query | yes |
| foreign_key | no_yes | no |
| identity_col | no_yes | no |
| seed | seed | yes |
| increment | increment | yes |
| data_col_id | col_id | yes |
| file_storage_sub_folder | sub_folder | yes |
| default_sort | no_yes | no |
| sort_no | sort_no | yes |
| sort_order | sort_order | yes |
| grp_until | no_yes | no |
| label_width | width | yes |
| field_width | width | yes |
| field_height_in_positions | no | yes |
| field_no_of_positions_further | no | no |
| form_field_in_next_grp | no_yes | no |
| form_next_grp_label | label | yes |
| form_next_grp_icon_id | icon_id | yes |
| field_in_next_col | no_yes | no |
| field_on_next_tab | no_yes | no |
| next_tab_label | label | yes |
| next_tab_icon_id | icon_id | yes |
| next_tab_default_expanded | no_yes | no |
| grid_col_width | width | yes |
| grid_field_in_next_grp | no_yes | no |
| grid_next_grp_label | label | yes |
| case_type | case_type | no |
| include_in_insert | no_yes | no |
| include_in_copy | no_yes | no |
| include_in_copy_to_clipboard | no_yes | no |
| allow_sort | no_yes | no |
| include_in_global_filter | no_yes | no |
| visible_for_filter | visible_for_filter_search | no |
| filter_condition | filter_condition | yes |
| filter_order_no | order_no | no |
| visible_for_search | visible_for_filter_search | no |
| search_condition | filter_condition | yes |
| search_order_no | order_no | no |
| trigger_for_update | no_yes | no |
| view_tab_id | tab_id | yes |
| view_col_id | view_col_id | yes |
| alias_col_id | alias_col_id | yes |
| col_description | description_multiline | yes |
| type_of_object | type_of_object | no |
| form_order_no | order_no | no |
| form_type_of_col | type_of_col | yes |
| grid_order_no | order_no | no |
| grid_type_of_col | type_of_col | yes |
| show_aggregation_in_grid | no_yes | no |
| aggregation_summary_type | aggregation_type | yes |
| card_list_type_of_col | type_of_col | yes |
| card_list_order_no | order_no | no |
| card_list_label | no_yes | no |
| card_list_field_height_in_positions | no | yes |
| calculated_field_type | calculated_field_type | no |
| calculated_field_query | query | yes |
| file_offline_available | no_yes | no |
| default_input | no_yes | no |
| default_output | no_yes | no |
| layout_input | no_yes | no |
| layout_type_output | no_yes | no |
| layout_mand_output | no_yes | no |
| context_input | no_yes | no |
| function_input | no_yes | no |
| parent_col_id | col_id | yes |
| use_for_optimistic_locking | no_yes | no |
| input_insert_handler | no_yes | no |
| input_update_handler | no_yes | no |
| has_alt_transl | no_yes | no |
| alt_transl_col_id | col_id | yes |

Enum values for `col`: `type_of_col`, `grid_type_of_col`, `form_type_of_col`, `card_list_type_of_col` — editable 0, read-only 1, hidden 3 (there is no 2). A `grid_type_of_col`/`form_type_of_col`/`card_list_type_of_col` equal to `type_of_col` is stored empty (inherited), so it reads back empty. `visible_for_filter`/`visible_for_search` — always 0, extended 1, never 2.

### `ref`
| Column | Domain | Nullable |
|---|---|---|
| model_id | model_id | no |
| branch_id | branch_id | no |
| ref_id | ref_id | no |
| ref_description | description_multiline | yes |
| source_tab_id | tab_id | no |
| target_tab_id | tab_id | no |
| ref_add | ref_add | yes |
| generate_ref_add_transl_object | no_yes | no |
| check_ref | no_yes | no |
| on_update | on_update | no |
| on_delete | on_delete | no |
| no_of_col | no_of_col | no |
| show_look_up | no_yes | no |
| different_look_up | no_yes | no |
| look_up_display_col_id | col_id | yes |
| look_up_control | look_up_control | no |
| refresh_combo_on_dropdown | no_yes | no |
| look_up_has_popup | no_yes | no |
| look_up_tab_variant_id | tab_variant_id | yes |
| show_detail | no_yes | no |
| detail_tab_variant_id | tab_variant_id | yes |
| order_no | order_no | no |
| abs_order_no | abs_order_no | no |
| screen_area_id | screen_area_id | yes |
| is_detail | no_yes | no |
| context_type_output | no_yes | no |
| alias_ref_id | alias_ref_id | yes |
| visible_for_filter_detail | visible_for_filter_search | no |
| visible_for_filter_look_up | visible_for_filter_search | no |

Enum values for `ref`: `on_delete` — no action 0, cascade 1, set null 2; `on_update` — no action 0, cascade 1.

### `ref_col`
| Column | Domain | Nullable |
|---|---|---|
| model_id | model_id | no |
| branch_id | branch_id | no |
| ref_id | ref_id | no |
| source_tab_id | tab_id | no |
| source_col_id | col_id | no |
| target_tab_id | tab_id | no |
| target_col_id | col_id | no |
| order_no | order_no | no |
| abs_order_no | abs_order_no | no |
| use_detail_null_comparison | no_yes | no |

---

## Reference summary

Key sources (consult if more detail needed):
- Domains: https://docs.thinkwisesoftware.com/docs/sf/domains
- Data model: https://docs.thinkwisesoftware.com/docs/sf/data_model
- Naming/subnames: https://docs.thinkwisesoftware.com/docs/sf/subnames
- Data modelling guidelines: https://community.thinkwisesoftware.com/news-blogs-21/data-modelling-guidelines-118
