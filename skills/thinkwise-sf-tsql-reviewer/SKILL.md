---
name: thinkwise-sf-tsql-reviewer
description: "Review T-SQL code written for the Thinkwise Software Factory platform and provide structured feedback on correctness, style, and Thinkwise-specific conventions. Works on any surface and needs no connector. When the code is a Software Factory control-procedure template (a fragment the Software Factory wraps into a generated procedure), it applies the template rules instead of full-object rules. ALWAYS trigger on the slash command /review. Also trigger when a user pastes T-SQL code and asks for a review, feedback, or check — including control-procedure templates (defaults, layouts, contexts, tasks, badges, handlers, triggers), stored procedures, functions, and views. Trigger when the user asks \"can you check this proc\", \"review my trigger\", \"what's wrong with this SQL\", \"does this follow Thinkwise conventions\", or pastes a code block containing CREATE PROCEDURE, CREATE TRIGGER, CREATE FUNCTION, CREATE VIEW, or ALTER equivalents. Also trigger for partial code snippets when the user asks if the logic is correct or idiomatic for Thinkwise."
---

# Thinkwise T-SQL Code Reviewer

## Purpose

Review T-SQL code written in the context of the Thinkwise Software Factory and provide a structured list of findings, each with a severity level, a clear explanation, and a concrete fix or suggestion. Works from pasted code alone; no connector is needed.

---

## Step 1 — Identify context

Before reviewing, determine:

1. **Template or full object.** Most Thinkwise code is a **control-procedure template**: a fragment the Software Factory weaves into a generated procedure, trigger or function. Signs: no `create`/`alter` header, no parameter list, and it uses the generated variables (`@cursor_from_col_id`, `@layout_mode`, `@badge_value`, `@<col>_type`, `inserted`/`deleted`, …) without declaring them. A hand-written object has its own `CREATE`/`ALTER` header. If unclear, assume a template and say so.
2. **Logic concept** — Default, Layout, Context, Task, Badge, Handler, Trigger, Process, Change detection, Subroutine, or View. Infer it from the variables used, the body, or the name; if unclear, make a reasonable assumption and state it.
3. **Dialect** — this skill reviews T-SQL. If the code is PostgreSQL, Oracle or DB2, say so and limit the review to logic and Thinkwise rules.

State your assumption at the top of the review output so the user can correct it if wrong.

When `thinkwise-sf-sql-logic` or `thinkwise-sf-control-procedures` is available, their concept references and `references/sql_style_guide.md` are the detailed source for sections B and F–L; the rules below are the review summary.

---

## Step 2 — Run the review checklist

Work through the checklist categories below. For each issue found, add a finding to the output (see Step 3 for format). Skip categories that are not applicable to the object type.

### A. Naming conventions

- Table names: lowercase, singular, underscores (e.g. `sales_order`, not `SalesOrders`)
- Column names: lowercase, underscore-separated
- PK column: `{table_name}_id` pattern (e.g. `sales_order_id`)
- FK columns: same name as the PK column in the parent table
- No `tbl_`, `col_`, `dttp_` or similar prefixes/meta info in names
- No lengths in names (not `name_50`, but `name`)
- No abbreviations except `id`, `nr`, `no`
- Generated object names come from the Software Factory, not the author: the Default procedure of a table is `def_<tab>`, its Layout `lay_<tab>`, its Context `ctx_<tab>` (program objects `default_<tab>`, `layout_<tab>`, `context_<tab>`). Never flag a template for a missing or "wrong" procedure name — it has none.
- Control procedure and template ids name the purpose (`calculate_order_total`), never the concept or code group (`default_order`, `layout_country`, `task`)

### B. Template rules (control-procedure templates only)

- The template is only the body. **Don't flag** `SET NOCOUNT ON`, `CREATE OR ALTER`, the parameter list, the standard variable declarations or the transaction wrapper as missing — the Software Factory generates them around the template.
- Flag a template that **declares** a generated variable (`@default_mode`, `@cursor_from_col_id`, `@<col_id>`, `@badge_value`, …) or adds its own `create`/`alter` header: it breaks the generated procedure.
- User messages go through `tsf_send_message '<msg_id>', <xml | null>, <abort>` — never `RAISERROR`, `THROW` or `PRINT`. On SQL Server, `abort = 1` does not stop execution by itself: in a batch task it needs `rollback; return;` after it.
- Fixed-value columns are compared and assigned by the element's `db_value`, with the element name in a comment after the value (`= 3 /* failed */`).
- Thinkwise house formatting: lowercase everywhere, leading commas, one column per line in `insert`/`select`/`update`/`merge`, `begin`/`end` after every `if`/`while`, one `select` to assign several variables, explicit column list on every `insert`.

### C. Parameter and variable conventions

- In a hand-written proc or function: parameters follow `@{column_name}` naming, matching the underlying column exactly; the PK parameter is present and correctly named; no extra parameters that don't map to a column or documented context variable; output parameters are justified
- In a template: the variables are fixed by the concept (see F–L); flag a variable that doesn't exist for that concept (e.g. `@layout_mode` in a Context)
- In a Handler update: the row is located with `@upd_<pk>` (current key), not `@<pk>` (new value)

### D. Data type usage

- `NVARCHAR` preferred over `VARCHAR` for text (unless charset restriction is intentional)
- `DATETIME2` preferred over `DATETIME` (never use `DATETIME` for new code)
- `INT` for identity PKs; `BIGINT` only for tables expected to exceed ~2 billion rows
- `BIT` for boolean flags (not `TINYINT`, `CHAR(1)`, etc.)
- `NUMERIC(p,s)` for amounts/quantities — avoid `FLOAT` or `MONEY`
- Avoid implicit type conversions in WHERE clauses or JOINs

### E. NULL handling

- `NULL`/`NOT NULL` is not valid on a variable declaration in T-SQL (only on table and table-variable columns) — never suggest adding it
- `ISNULL` / `COALESCE` used correctly and consistently with the rest of the codebase
- No silent NULL propagation in calculations that could produce unexpected results
- A variable filled by `select @x = … from …` keeps its previous value when no row matches — initialize it or check `@@rowcount` where that matters

### F. Default (`def_<tab>`)

- No DML on tables (`insert`/`update`/`delete`) — the record isn't committed yet. Reading other tables with `select` (look-ups) is fine
- Each block is guarded on `@cursor_from_col_id` (the field just left; empty on the initial pass — check both `is null` and `= ''`), so it doesn't fight the user's typing
- Where a suggested value must not overwrite one the user typed, it fills only when empty (`and @col is null`) — don't demand this pattern where the value should always track its source
- Messages are allowed to inform: `tsf_send_message …, 0`. A Default never aborts (`abort = 1`) — it corrects the value and informs
- No cursors, temp tables or explicit transactions

### G. Layout (`lay_<tab>`)

- Sets only outputs: `@<col>_type` (0 editable, 1 read-only, 2 hidden in form, 3 hidden outside form), `@<col>_mand`, and `@add_button_type`/`@update_button_type`/`@delete_button_type`/`@confirm_button_type`/`@cancel_button_type`
- Stateless: sets a value only where it must differ from the model default; no "reset" assignments, no reliance on a value persisting
- Can only restrict what the model allows, never widen it
- Branches on `@layout_mode` (0 add, 1 update, 2 navigate) where modes differ; never assigns a column value (that is a Default)
- No DML, no messages, no cursors, temp tables or transactions — it runs on every UI event

### H. Context (`ctx_<tab>`)

- Sets only availability outputs: `@<ref_id>_type`, `@<task_id>_type`, `@<report_id>_type` (0 enabled, 1 disabled, 2 hidden), and optionally `@active_target_ref_id`
- Ids are the real ones from the model (`ref_…` reference ids, task and report ids) — flag guessed ids
- Has no `@layout_mode`/`@import_mode`; stateless; only restricts
- No DML, no messages, no cursors, temp tables or transactions

### I. Task

- May do DML, call procedures and send messages; validations abort with `tsf_send_message '<msg>', null, 1`
- Transactions: check whether the code group's generated wrapper already provides them before flagging a missing or extra `begin tran` — the template of an atomic task holds only the business logic
- Set-based over cursors; an unavoidable cursor is `local static read_only forward_only`, with each iteration in its own transaction
- Long-running work reports progress with `tsf_send_progress`

### J. Badge

- Assigns only `@badge_value`; one cheap query — it runs on an interval and after every data change
- No DML, no messages, no transactions, no cursors or temp tables
- Honours its context parameters: scoped when the FK parameter is filled, across the board when it is null (`(@<fk> is null or t.<col> = @<fk>)`)
- `null` hides the badge, `0` shows a `0` bubble — check the intent (`nullif(count(*), 0)`)

### K. Handler

- Uses the correct parameter set matching the table definition (insert: all columns; update: all columns plus `@upd_<pk>`; delete: PK only)
- DML only on its own table and child tables of its own entity — not on a parent or another entity
- No explicit transaction — the generated handler is already atomic
- Custom validations use `tsf_send_message …, 1` — not `RAISERROR`/`THROW`, and not silent failures
- Avoids re-implementing what the generated statement already does; only augments or deliberately replaces it
- Insert with an identity PK sets the output (`set @<pk> = scope_identity()`) where the generated statement doesn't

### L. Trigger

- `AFTER INSERT`, `AFTER UPDATE`, `AFTER DELETE` preferred; `INSTEAD OF` only if explicitly justified
- Every statement works set-based through `inserted` / `deleted`; never assumes a single row
- No cursors, variables, temp tables or explicit transactions; never modifies `inserted`/`deleted`
- A recursive CTE can't feed an `if`/`exists` — flag it (deploy-time syntax error)
- User-facing errors go through `tsf_send_message`, not `PRINT`/`RAISERROR`
- Does not call procs or insert/delete into business tables (that work belongs in a Handler or Task)

### M. View / report query patterns

- No `SELECT *` — columns are explicitly listed
- Aliases are clear and match Thinkwise column naming conventions
- JOINs use explicit `INNER JOIN` / `LEFT JOIN` syntax (no implicit comma joins)
- Filtering logic is consistent with what the SF platform can push down (no `distinct`, bare `union`, or filter on an outer join's nullable side in a view)
- Computed columns use clear, deterministic expressions

### N. General T-SQL quality

- No `SELECT *` anywhere
- Consistent indentation and readability
- No hard-coded values that should be parameters or configurable
- Hand-written full objects only (not templates): `SET NOCOUNT ON` at the top of procs, and `CREATE OR ALTER PROCEDURE` instead of `DROP / CREATE` patterns
- No deprecated syntax (`=*`, `*=` joins, `!<`, `!>`)
- Every `begin tran` has a matching `commit tran` and `rollback tran`
- **Aggregate over an outer reference (Msg 8124):** inside a subquery or `APPLY`, an aggregate whose argument combines a column of the outer query with another column (`SUM(n.digits * p.pos)` with `n` outer) fails on SQL Server when the code is compiled — at deploy, or when a SQL-assignment `control_proc_code` that contains it runs — not when the Software Factory generates the code group, so a clean generate proves nothing. Flag it and suggest computing the expression per row in a derived table first, then aggregating that column: `SELECT SUM(x.weight * x.digit) FROM (SELECT <expr> AS weight, <expr> AS digit FROM …) x`. PostgreSQL accepts the mixed form, so it slips through on templates written for both platforms

### O. Performance patterns

- **Parameter sniffing risk:** if a proc filters on a parameter that maps to a highly skewed column (e.g. status, type, country), flag that the compiled plan will be based on the first execution's value and may perform poorly for other values. Mitigation options: `OPTION (RECOMPILE)` on the specific statement, local variable copy of the parameter, or `OPTIMIZE FOR` hint
- **Sargability:** predicates on columns should not wrap the column in a function (e.g. `YEAR(order_date) = 2024` is non-sargable; `order_date >= '2024-01-01' AND order_date < '2025-01-01'` is sargable). Flag any function-wrapped column in a WHERE clause
- **`WITH (NOLOCK)`:** flag any use of `WITH (NOLOCK)` — it takes a schema stability lock anyway, can return dirty or phantom reads, and is not a substitute for proper isolation level design (Brent Ozar). Note it in findings with explanation
- **Implicit conversions:** warn when a parameter type doesn't exactly match the column type (e.g. `VARCHAR` parameter on an `NVARCHAR` column) — causes a table scan instead of an index seek
- **Set-based vs. row-by-row:** flag cursors, `WHILE` loops over tables, and scalar UDFs called per-row — these serialize execution and kill performance at scale. Suggest set-based rewrites
- **`sp_executesql` for dynamic SQL:** if dynamic SQL is present, verify it uses `sp_executesql` with parameterized queries rather than string concatenation with `EXEC(@sql)` — prevents SQL injection and enables plan cache reuse (Microsoft docs)
- **Unnecessary `DISTINCT`:** flag `DISTINCT` inside a `UNION` (redundant — `UNION` already deduplicates) or on a query where the uniqueness is already guaranteed by the data model
- **`UNION` vs. `UNION ALL`:** expect `UNION ALL` by default. Accept `UNION` only when duplicates must go and the queries don't already guarantee distinct rows (they can overlap), with a comment on the line before saying why. Flag a bare `UNION` — the sort/deduplication costs performance and often hides the intent

### P. Security

- **SQL injection:** flag any dynamic SQL built by concatenating user-supplied values without `sp_executesql` parameterization
- **`sp_` prefix:** flag proc names starting with `sp_` — SQL Server searches master first for these, causing unnecessary lookups and potential name collisions with system procs (Microsoft docs)
- **Least privilege:** flag if the proc directly accesses objects outside the expected schema without justification
- **Sensitive data:** flag if the proc exposes columns that look like personal data (e.g. `password`, `ssn`, `bsn`, `credit_card`) without any masking, encryption reference, or comment explaining why access is appropriate

---

## Step 3 — Output format

Start with a one-line context statement, then produce a findings table.

```
**Context assumed:** {template | full object} — {logic concept} on {table/task}

| # | Severity | Category | Finding | Suggested fix |
|---|----------|----------|---------|---------------|
| 1 | 🔴 Error   | Default  | `update` on `customer` inside a Default — the record isn't committed yet | Move the update to a Trigger or Task; keep only the assignment to `@credit_limit` |
| 2 | 🟡 Warning | Template | `raiserror` used for a validation message | `exec tsf_send_message 'credit_limit_exceeded', null, 0` |
| 3 | 🔵 Info   | Style    | `where status = 3` has no element comment | `where status = 3 /* blocked */` |
```

**Severity levels:**

| Level | When to use |
|-------|-------------|
| 🔴 Error | Will break at runtime, violates a hard Thinkwise constraint, or causes incorrect data |
| 🟡 Warning | Does not follow Thinkwise convention, may cause subtle bugs, or will cause issues at scale |
| 🔵 Info | Style, readability, minor improvement — won't cause problems but is worth fixing |

After the table, add a short **Summary** paragraph (2–4 sentences) that synthesises the overall quality, highlights the most important issues, and gives a concrete next-step recommendation.

If no issues are found, say so explicitly and briefly explain why the code looks correct.

---

## Step 4 — Offer follow-up

After the review, offer:

- "Want me to rewrite the code with all fixes applied?"
- "Should I focus on any specific finding in more detail?"

Keep the offer brief — one or two lines.
