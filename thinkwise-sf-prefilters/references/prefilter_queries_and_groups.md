# Prefilter query structure, states, and groups

Loaded on demand from `thinkwise_sf_prefilters`.

## Query structure

A query-based prefilter is a boolean SQL expression dropped into the table's `where` clause. The
current row is always aliased `t1`:

```sql
t1.order_date < getdate
```

**Verified: `tab_prefilter` has no `rdbms_type` dimension** — unlike `control_proc_template`, which is
keyed per dialect (see `thinkwise_sf_control_procedures`), there is exactly one
`query` string per prefilter, applied against every enabled RDBMS. If `branch_rdbms_type` for the
model has more than one row, write portable SQL (avoid dialect-specific functions —
`getdate`/`now`/`sysdate`, `top n`/`limit`, string-concat operators) or restructure the condition
so it doesn't need one — there is no per-dialect override slot the way a template-backed view or
control procedure has.

Four real examples, confirmed against a live reference model:

**Relative date, via a calendar table** (`hour_analysis.current_week`):
```sql
exists (
    select 1
      from date_helper dh
     where dh.iso_date = cast(getdate as date)
       and dh.iso_week = t1.week
       and year(iso_date) = t1.year
   )
```
Comparing to `getdate` rules out a plain column condition — the value isn't static.

**"My records", via the current user** (`email.my_emails_employee`):
```sql
exists (
    select 1
      from application_settings a
     where a.standard_employee_id = t1.employee_id
   )
```
A per-user settings table keyed off a `dbo.tsf_user`-style function is the standard way to reach
"the logged-in user" from SQL. The same shape repeats for `my_customers`, `my_declaration`,
`my_emails_contact` — always an `exists` join through the same per-user settings table.

**Data-quality check, via a correlated count** (`activity.untranslated`):
```sql
8 <> (select count(1) from activity_translated t where t1.activity_id = t.activity_id)
```
`8` is the number of active application languages; the prefilter flags any row missing a translation
row for one of them. Generalizes to any "should have exactly N related rows" completeness check.

## Prefilter states

Every prefilter carries three independent states — `main_prefilter_state`, `detail_prefilter_state`,
`look_up_prefilter_state` — so the same prefilter can behave differently on the main grid, a detail
grid, and a reference field's popup. Confirmed enum, all three fields:

| State | Value | Visible | Active | User can change it |
|---|---|---|---|---|
| Off hidden | 0 | No | No | No |
| Off | 1 | Yes | No | Yes — can turn on |
| On | 2 | Yes | Yes | Yes — can turn off |
| On locked | 3 | Yes | Yes | No |
| On hidden | 4 | No | Yes | No |

`On hidden` is how a prefilter becomes a silent data-authorization filter — the condition always
applies and the user never sees the control. Use `look_up_prefilter_state` on its own (leaving
Main/Detail at Off) to narrow a reference field's popup — e.g. a project picker offering only *active*
projects — without touching what the table shows on its own screen.

**A table variant may only tighten a prefilter's state relative to the base table** (On → On hidden is
fine; On hidden → Off is rejected) — documented platform behavior, not independently re-verified
against `tab_variant_prefilter_overview` validation in this pass. If a genuinely looser state is
needed somewhere, model a second variant rather than fighting the check.

**Role-based "Always on" / data-authorization** can force a prefilter to `On hidden` for a specific
role regardless of what the active variant says (Access control → Model rights → Tables → Prefilters →
Roles, per platform docs). The role/rights entity backing this was **not found** among the
`manage_datamodel`/`manage_screentypes`-style domains checked here — none of the domains a connector
exposed included a `role_tab_prefilter_overview`-shaped entity. Check the connector's own domain list
for a security/IAM/rights-style domain before assuming this is unreachable through it.

## Prefilter groups

`allow_multiple_active_prefilters = false` makes a group behave like a radio button: zero or one
member active at a time. Setting it `true` allows several members active together, combined per
`filter_mode`:

- **Match all (AND)** — a row must satisfy every currently-active prefilter in the group.
- **Match any (OR)** — a row must satisfy at least one active prefilter in the group. **Universal UI
  only** — the Windows GUI keeps at most one active prefilter per group no matter this setting.

Thinkwise's own illustrative case for match-any: a status column with Draft / Active / Paid / Payment
rejected prefilters in one group. Turn on Draft and Active together and you see records matching
*either* — AND would return nothing, since a row can't hold two status values at once. This is the
general rule for any group of mutually-exclusive category values: **match any**, not match all.

A **mandatory** match-any group is also the standard way to build category-level authorization: put
Red/Green/Blue in a mandatory OR group, then set Red to `Off hidden` for roles that shouldn't see red
records. Turning a member on in an OR group *widens* the result set rather than narrowing it — so
`Off hidden` there means "this role's Red toggle doesn't exist," not "Red data is blocked" — a common
point of confusion when authorization is layered onto an OR group.

Two groups observed in a live model, for contrast — the first is the same `declaration_lines.status`
match-all anomaly called out in "Plan first" above (see there for the full explanation):

| Table | Group | Multiple active | Mode | Members |
|---|---|---|---|---|
| `declaration_lines` | `status` | Yes | Match all | `approved`, `cancelled`, `paid`, `to_be_approved` |
| `email` | `read_or_unread` | No | — | `read`, `unread` |
