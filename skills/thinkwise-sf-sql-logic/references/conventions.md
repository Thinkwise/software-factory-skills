# Shared conventions

Cross-cutting helpers and rules that apply across logic concepts. Concept references
point here instead of repeating it. All of this is self-contained; no need to leave for
external docs.

---

## Messages — `tsf_send_message`

Send a modelled message from a template. Prefer this over `raiserror` (SQL Server) or
`signal sqlstate`. The call does **not** wait for user input: code flow continues, or
aborts, immediately.

```
tsf_send_message [message_id], [parameter_string], [abort]
```

- **`message_id`** — the Message id modelled in the Software Factory (menu
  *User Interface > Messages*), translated in its Translations tab. Passed as the
  modelled id, e.g. `'duplicate_customer'`.
  Two special ids, code-only (never as a task confirmation or process message):
  - `clear_panel` — clear the message panel.
  - `add_separator` — add a separator line to the panel.
- **`parameter_string`** — optional XML string that fills the parameters in the
  message translation, or `null`. It can also embed translations of model objects such
  as columns or tables.
  - Literal parameters: `'<text>Thinkwise</text><tab tabid="customer" transl="standard"/>'`
    might render as "Note, Thinkwise already exists as a Customer".
  - From variables, build the XML first:
    ```sql
    declare @xml nvarchar(500) = concat(
         (select @var1 for xml path('text'))
        ,(select @var2 for xml path('text'))
    )
    exec dbo.tsf_send_message 'message_with_parameters', @xml, 1
    ```
- **`abort`** — what should happen when the message occurs. Dialect-specific:
  - **SQL Server**: `0` = continue (database severity 9, informational);
    `1` or `null` = the action is considered reversed (severity 16). SQL Server does
    **not** roll back automatically, so an abort needs an explicit `rollback; return;`
    where a transaction is open:
    ```sql
    exec tsf_send_message 'duplicate_customer', null, 1;
    rollback;
    return;
    ```
    Inside a `try/catch`, the code above jumps straight into the `catch` block.
  - **Oracle**: `true` = `raise_application_error` (aborts the transaction);
    `false` = `dbms_output.put_line`.
  - **DB2**: the abort parameter is ignored — sending a message always aborts the
    transaction. To still show an informational message from a Default or Layout on DB2,
    those concepts expose an extra `v_message_text` variable to set instead.

Concept-specific note: a **Default** only ever uses `abort = 0` (it corrects a value and
informs). Aborts belong to concepts that run at or after commit, such as Triggers and
Tasks.

Related procedures (same message framework): `tsf_send_progress` (progress messages
during long operations; not supported on DB2) and `tsf_send_assertion_msg`.

---

## Username — `tsf_user()` / `tsf_original_login()`

Retrieve the application user, which cannot be read via `user_name()`, `system_user` or
`USER` when connection pooling or IAM authentication is used.

- `tsf_user()` — the current user, or the simulated user when a user is being simulated.
- `tsf_original_login()` — the actual login from the session context. Works only with
  Indicium; without it, it behaves like `tsf_user()`.

Call syntax per dialect:

```sql
-- SQL Server
select dbo.tsf_user();
-- Oracle
select tsf_user() from dual;
-- IBM i DB2
select tsf_user() from sysibm.sysdummy1;
-- PostgreSQL
select public.tsf_user();
```

Crystal Reports and the *Generate report* process action do not support this (they
return the pool user); pass the username in as a parameter filled by a Default that uses
`tsf_user()`.

---

## Domain elements (fixed value lists)

When a column or parameter is backed by a domain with a fixed value list, program on the
elements rather than magic literals.

- **To store or compare a value, use the raw `db_value`.** The `get_sf_metadata` output
  gives both `db_value` and `elemnt_id`; if the user names a value ("set status to
  Confirmed"), match `elemnt_id = Confirmed` and use its `db_value`.
- `get_dom_elemnt_id('domain', db_value)` resolves the element id when you specifically
  need the id itself.

---

## Naming (control procedures and templates)

Only relevant when asked to name a control procedure or template. The id should describe
the purpose, carry no meta information, and never be just a table name — except a view's own
`SELECT`, whose control procedure may be named exactly after the view (see `thinkwise-sf-views`,
"Naming"). Leave out concept
and code-group words (`default`, `layout`, `trigger`, `task`, …) — the same naming rule as
`thinkwise-sf-control-procedures` (`references/sql_authoring.md`, "Naming guidelines").

- Good: `calculate_order_total`, `generate_country_layout`, `validate_project_budget`.
- Bad: `default_order`, `layout_country`, `trigger_project`, `default`, `task`.

If a control procedure holds a single template, the template id matches it; with multiple
templates, each template id differs and is atomic (one piece of functionality, no
dependency on another template).

---

## SQL formatting (Thinkwise house style)

Every emitted fragment follows the Thinkwise SQL formatting guidelines so a developer can
paste it without reformatting. The authoritative tool is the Redgate SQL Prompt "Thinkwise"
formatting style; match its output.

**Do:**

- **Lower case only** — keywords, built-in functions, datatypes and identifiers.
- **Leading commas** — put the comma in front of each column/item, not at the end.
- **Indent with spaces, not tabs**; indent nested blocks.
- **`begin` / `end` after every `if` and `while`** condition (also a coding rule).
- **Align** aliases (`as ...`), `join` / `on`, comparison operators, and `and` / `or` in a
  `where`.
- **Align opening and closing brackets** on the same column.
- **Column lists for inserts**; give every calculated value or literal an alias.
- **Comment each block**, and put a short `--` comment after each domain value or literal
  saying what it means.

**Don't:**

- Use reserved keywords as identifiers.
- Leave commented-out development code (stray variable assignments, helper queries).

**Canonical shapes:**

```sql
-- select: leading commas, aligned aliases, a comment after each literal
select si.sales_invoice_id
      ,si.invoice_date
      ,si.amount_incl_vat as amount   --gross amount
from sales_invoice si
where si.invoice_status = 2           --sent
```

```sql
-- if: begin/end, aligned comparisons and and/or, literal comments
if exists (select 1
           from order_line ol
           where ol.order_id     = @order_id
             and ol.line_status  = '10' --new
          )
begin
    set @has_open_lines = 1
end
```

```sql
-- where: aligned operators with an or-group
where oh.order_status         = '20'   --in progress
  and (   oh.priority          = 1     --high
       or oh.customer_vip      = 1     --vip customer
      )
```

```sql
-- insert: column list, leading commas, brackets aligned on the same column
insert into order_line(order_id
                      ,product_id
                      ,quantity
                      )
select @order_id
      ,ol.product_id
      ,ol.quantity
from order_line_template ol
where ol.template_id = @template_id
```

---

*Source: Thinkwise documentation (Messages, Username, Control procedure guidelines, SQL
coding guidelines, SQL formatting guidelines). Captured here so the skill is self-contained.*
