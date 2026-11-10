# Change detection

## What it does and when it fires

Change detection tells the user interface, just before an automatic refresh, whether a
subject has actually changed and therefore needs to be refreshed. It exists only for
**subjects** — tables and views — not for tasks or reports, which have no data.

It runs only in combination with the auto-refresh functionality: every time an auto-refresh
is due, the UI calls this logic and it can conditionally prevent the refresh (leave the data
as is) or allow it. Enabling change detection on a subject **without** providing code
disables auto-refresh altogether, so if you switch it on you must implement it.

---

## Deliverable and object

Change detection becomes a stored procedure named `chg_<subject>`, where the subject is the
table or view id. The deliverable is only the fragment that conditionally sets
`@refresh_data` — no `create procedure`, no parameter list, no `set nocount on`, no `grant`.

---

## Fixed variables (provided by the generated proc — do NOT declare them)

| Variable            | Direction | Meaning |
|---------------------|-----------|---------|
| `@variant_id`       | in        | `varchar(128)`; the variant of the current subject, `NULL` when no variant is involved. |
| `@last_refresh_utc` | in        | `datetime2`; the UTC timestamp of the last refresh. Compare change timestamps against this. |
| `@refresh_data`     | **out**   | `bit`; default `0` (no refresh). Set to `1` to tell the GUI a refresh is needed. |
| `@<fk_col>`         | in        | one parameter per lookup/foreign-key column of the subject; lets detection run in the context of a parent record (for example on a detail screen). |

Take the foreign-key/lookup columns from the pasted `get_sf_metadata` output (the subject's
FK columns / `lookup_refs`); do not invent them.

---

## Hard rules

- **Optimal performance always.** This runs before every auto-refresh, so keep it a single
  cheap existence check. Avoid cursors, temp tables and heavy joins; an index on the change
  timestamp helps.
- **Read-only.** Only assign `@refresh_data`; never do `insert`/`update`/`delete`.
- **No messages, no transactions, no cursors.**
- **Default is no refresh.** Leave `@refresh_data` untouched (it stays `0`) when nothing has
  changed; only set it to `1` on a detected change.
- **Compare in UTC.** `@last_refresh_utc` is UTC. If the subject stores local trace
  timestamps, convert them to UTC before comparing; if timestamps are already stored in UTC,
  compare directly.
- **Honour context parameters.** On a detail screen, scope the check to the supplied FK so a
  refresh is triggered only for the relevant parent record.

This concept relies on trace fields (an insert/update timestamp on the subject); make sure
those exist before implementing it.

---

## Core idioms

**1. Refresh when a record changed since the last refresh** (local trace timestamp converted
to UTC):

```sql
if exists (select 1
           from order_header oh
           where oh.update_date_time at time zone 'W. Europe Standard Time' at time zone 'UTC' >= @last_refresh_utc
          )
begin
    set @refresh_data = 1
end
```

**2. Timestamps already stored in UTC** — compare directly, no conversion:

```sql
if exists (select 1
           from order_header oh
           where oh.update_date_time_utc >= @last_refresh_utc
          )
begin
    set @refresh_data = 1
end
```

**3. Context-scoped** — only look at the parent record's rows on a detail screen:

```sql
if exists (select 1
           from order_header oh
           where oh.customer_id = @customer_id
             and oh.update_date_time at time zone 'W. Europe Standard Time' at time zone 'UTC' >= @last_refresh_utc
          )
begin
    set @refresh_data = 1
end
```

---

## Worked example

Change detection on an order subject: refresh when any order has been inserted or updated
since the last refresh, scoped to the customer when the subject sits on a customer detail
tab and looked at overall otherwise:

```sql
-- Refresh if an order changed since the UI last refreshed (compared in UTC)
if exists (select 1
           from order_header oh
           where (@customer_id is null or oh.customer_id = @customer_id)
             and oh.update_date_time at time zone 'W. Europe Standard Time' at time zone 'UTC' >= @last_refresh_utc
          )
begin
    set @refresh_data = 1
end
```

---

## Dialect note

The `at time zone … at time zone 'UTC'` conversion is SQL-Server syntax. Time-zone handling
differs on Oracle, DB2 and PostgreSQL, so on those platforms convert to UTC with the
platform's own mechanism rather than only swapping the variable prefix.

---

## Output checklist

- [ ] Only the fragment — no `create procedure`, no parameter declarations, no `grant`.
- [ ] Assigns `@refresh_data = 1` only on a detected change; leaves it `0` otherwise.
- [ ] A single cheap existence check; read-only, no messages, no transactions.
- [ ] Change timestamps compared against `@last_refresh_utc` in UTC.
- [ ] Context FK parameters honoured with `(@<fk> is null or <col> = @<fk>)` where relevant.
- [ ] Short `--` comments explain the intent; `@` for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
