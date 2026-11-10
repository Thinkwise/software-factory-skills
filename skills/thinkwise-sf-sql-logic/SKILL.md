---
name: thinkwise-sf-sql-logic
description: >
  Write the SQL for a Thinkwise Software Factory business logic concept: the fragment that
  goes inside a control-procedure template. Covers Default, Layout, Context, Process, Trigger,
  Task, Handler, Function, Badge, Change detection, Subroutine and Prefilter, and can produce
  parameterized templates and dynamic (SQL) assignment code (template plus control_proc_code
  that populates staging tables). ALWAYS trigger on the slash command /logic. Also trigger
  when the user wants to write, generate, extend or fix the SQL for one of these concepts in a
  Thinkwise / Software Factory context (for example: a default that fills a field, a
  conditional mandatory field, updating another table after insert, a badge count, or applying
  a template across many tables), even when they do not name the concept. When
  triggered by natural language, first confirm the concept before writing code; the user can
  override. Defaults to SQL Server (T-SQL), infers Oracle/DB2/PostgreSQL from context.
  Works on any surface, with or without a connector: takes table context from pasted
  get_sf_metadata JSON, or reads it from the Software Factory when an Indicium MCP
  connector is present.
---

# Thinkwise SQL Logic

Produce **only the logic fragment** that a developer pastes inside a Thinkwise
control-procedure template. The Software Factory generates the surrounding
`create/alter`, the parameter list and the standard variable declarations, so this
skill never emits those. For a default that fills a total, the whole deliverable is
something like `set @order_total = @price + @vat` — nothing more.

Each logic concept has its own reference file under `references/` describing its fixed
variables, hard rules, idioms and worked examples. This SKILL.md is the router: it
decides which concept applies, confirms with the user, then loads that reference and
follows it.

---

## Step 0 — Dialect and version

- **Default is SQL Server (T-SQL)**, with variables prefixed `@` (e.g. `@order_total`).
- If the context indicates **Oracle or DB2** (the user says so, or the pasted metadata
  clearly comes from such a model), keep the template identical but replace the `@` prefix
  with `v_` on every variable (`@order_total` -> `v_order_total`). When a generated
  procedure of the model can be read (through a connector, or pasted by the user), check its
  prefix first and follow it — `thinkwise-sf-control-procedures`
  (`references/code_type_variables.md`) treats the generated procedure as the source for
  Oracle/DB2 names.
- On **PostgreSQL** the generated procedure names task and subroutine parameters, columns
  and the code type's variables `p_<id>` (`p_<alias>` for a task parameter with an alias),
  and process-step switches `p_<step_id>`. Use `v_<name>` only for a local the template
  declares itself. PL/pgSQL resolves names at run time, so a wrong prefix passes code
  generation and fails only when the procedure executes. PostgreSQL also needs its own
  syntax (`:=` for assignment, `if … then … end if;`), not only another prefix.
- The skill is **version-agnostic**. The pasted `get_sf_metadata` JSON may be compact
  or non-compact and may come from an older platform version, so read it defensively:
  fall back gracefully when a field is absent and never assume a key exists.

---

## Step 1 — Get the table context

You need the table and column names, domains, datatypes, FK relations, fixed value lists
(`db_value` + `elemnt_id`), tasks and reports. Two sources:

- **An Indicium MCP connector is present** — read the context from the Software Factory
  directly instead of asking for a paste: `col` (columns, `dom_id`, keys), `dom` and
  `elemnt` (datatypes and value lists), `ref`/`ref_col` (references, with their `ref_id`),
  `tab_task`/`tab_report` (tasks and reports on the table), filtered on the model and branch
  pinned by `thinkwise-sf-base`. The concept references' rules for `get_sf_metadata` fields
  apply to the same facts read this way.
- **No connector** — the user pastes the `get_sf_metadata` output (JSON) into the
  conversation: `detail_refs` / `lookup_refs` for FK relations, `domain_elements` for value
  lists, `tasks` and `reports`.

If no metadata is present and the target table or columns are unclear, ask the user to
paste the `get_sf_metadata` output, or at least to name the table and the relevant
columns. Do not invent column or table names.

If the user does not have `get_sf_metadata` installed, or wants a quick one-off, offer the
static query at `assets/metadata_query.sql` instead. It is the procedure's compact logic
inlined as a plain batch, so it returns the **same JSON shape**; the user runs it and pastes
the JSON, which you read exactly as the procedure's output. The query body is a fixed
template, never retyped from memory; the `declare` block at the top (identity values plus
the `@include_*` flags) is meant to be tuned per request — follow the copy/edit/deliver
workflow and the flag-selection table in `references/metadata_query.md` exactly, so the
query the user gets is always byte-identical to the asset apart from those declared values.

For a **Context**, the metadata must also include the detail-tab references, tasks and
reports (the `detail_refs` / `lookup_refs`, `tasks` and `reports` sections — all on by
default), because their ids are what a Context addresses. See `references/context.md`.

For **dynamic assignment** (Step 2b) this step does not apply: the selection runs against
the SF meta-model (`references/sf_metamodel.md`), so no `get_sf_metadata` paste is needed.

---

## Step 2 — Determine the concept

Infer the concept from the request using this map. The object column tells you what
the generated result is; the reference column tells you which file to load in Step 4.

| Request sounds like...                                                                 | Concept          | Object          | Reference               |
|----------------------------------------------------------------------------------------|------------------|-----------------|-------------------------|
| Set/derive field value(s) from other fields in the current row, during entry           | Default          | proc fragment   | `references/default.md` |
| Make a field visible / editable / mandatory; enable or disable data-manipulation buttons| Layout           | proc fragment   | `references/layout.md`  |
| Control which tasks / reports / detail tabs are available; set the active detail tab    | Context          | proc fragment   | `references/context.md` |
| After a process action, decide which follow-up actions run and in which order           | Process          | proc fragment   | `references/process.md` |
| After insert/update/delete, update other rows/tables or reverse a transaction           | Trigger          | trigger         | `references/trigger.md` |
| Standalone business functionality, also callable from other logic                       | Task             | proc fragment   | `references/task.md`    |
| Override the insert/update/delete DML with custom behaviour                              | Handler          | proc fragment   | `references/handler.md` |
| Reusable calculation used by other logic                                                 | Function         | function        | `references/function.md`|
| The number shown on a subject/task/report badge                                          | Badge            | proc fragment   | `references/badge.md`   |
| Decide whether a subject changed and needs a refresh                                     | Change detection | proc fragment   | `references/change_detection.md` |
| A generic subroutine that supports other logic                                          | Subroutine       | proc/function   | `references/subroutine.md` |
| Show only the rows meeting fixed criteria, as a toggleable predefined filter (no user input) | Prefilter        | where-clause    | `references/prefilter.md` |

For a second opinion, this is the official Thinkwise "when to use which functionality"
guide, mapping a functional wish to a program object:

| Functional wish                                                          | Concept          |
|--------------------------------------------------------------------------|------------------|
| Make a field mandatory, or hide fields, based on conditions              | Layout           |
| Hide the Add / Update / Delete button based on data                      | Layout           |
| Hide tasks or reports based on data                                      | Context          |
| Hide detail tabs based on data                                           | Context          |
| Calculate a value while editing                                          | Default          |
| Calculate a value for the current or parent record after saving/deleting | Trigger          |
| Perform a check on the record's own data only, after saving              | Check constraint |
| Perform a check using other records, after saving                        | Trigger          |
| Populate a detail table after saving                                     | Handler          |
| Start a process or change a status                                       | Task             |
| Execute multiple steps in sequence                                       | Process (flow)   |

`Check constraint` is declarative: it is modeled on the table, not written as a code
fragment, so this skill does not emit it. If the wish lands there, tell the user it belongs
in the data model as a check constraint rather than in a control procedure. Its condition
uses the table's own columns only, with column names in double quotes and no alias
(`"threshold_percentage" between 0 and 100`). A check on one entered value belongs in an
input constraint on the domain instead: a SQL expression (type 0, on change) refers to the
value as `t1.<dom_id>` (`t1.dom_amount >= 0`), or a regular expression (type 1) matches
the input; its message is the translation of type 977.

The hardest boundary is "set a value": a **Default** acts on the current row during
entry (front-end, before commit, read-only on other tables); a **Trigger** acts after
commit and may write to other rows and tables. The confirmation in Step 3 exists partly
to catch this.

**Trigger vs Handler** is the other boundary worth checking up front. Both react to
insert/update/delete, but a Trigger is set-based and must not call procedures, work
row-by-row, insert/delete into business tables, or populate detail tables; those belong
in a Handler. If the request needs any of that, lean Handler. See the "Trigger or Handler?"
section in `references/trigger.md`.

---

## Step 2b — Determine the assignment mode

Independently of the concept, decide how the fragment is delivered. Three modes:

- **Static, no parameters** — a single fragment for one object. Base behaviour: continue to
  Step 3 and deliver the plain fragment.
- **Static, parameterized** — one template reused across objects with per-object values. Load
  `references/parameters.md`. Deliver the bracketed template plus a parameter overview.
- **Dynamic (SQL assignment)** — the fragment must be applied across many objects chosen by a
  rule ("every table with column X", "all tasks tagged Y"). Load
  `references/dynamic_assignment.md` and `references/sf_metamodel.md`. Deliver two SQL files:
  the template and the `control_proc_code`.

Signals for dynamic: the request quantifies over objects ("all/every tables/tasks that..."),
or selects by column presence or by tag. Signals for parameterized: the same logic repeats
across objects with only names differing. When unsure, confirm the mode in Step 3.

For dynamic and parameterized modes the metadata need is different: dynamic assignment reads
the **SF meta-model** (`references/sf_metamodel.md`), not `get_sf_metadata`, because it
selects SF objects rather than reasoning about one end-product table.

---

## Step 3 — Confirm the concept (before writing anything)

Ask with the structured question tool — `ask_user_input_v0` in claude.ai/ThinkIT,
`AskUserQuestion` in Claude Code — or, without either, a short numbered question in text.
Never write code before the concept is confirmed, and always allow an override.

- **Invoked via `/logic`** — intent is explicit. Confirm only the concept:
  "I think this is a **Default**. Is that right?" with options
  `Yes, Default` / `No, another concept`. On "another concept", present the concept list.
- **Auto-triggered by natural language** — first confirm both that logic is wanted and
  which concept: options `Yes, {concept}` / `Another concept` / `No, never mind`. On
  "No, never mind", stop and step back.
- If the assignment mode (Step 2b) is ambiguous, confirm it here too:
  `Static` / `Static with parameters` / `Dynamic (SQL)`.

---

## Step 4 — Load the concept reference

Read `references/{concept}.md` and follow it. Each reference is authoritative for its
concept: the fixed variables you may use (but must not declare), the hard rules, the
idioms and the worked examples. Do not rely on memory for a concept's variables — read
its file.

---

## Step 5 — Resolve the target columns

From the request plus the metadata, work out which columns are read and which are
written. If it is genuinely ambiguous (which column holds the total, which field should
trigger it), ask one focused question rather than guessing.

---

## Step 6 — Output

Deliver according to the assignment mode (Step 2b):

- **Static, no parameters** — emit only the fragment.
- **Static, parameterized** — emit the bracketed template and the parameter overview; follow
  `references/parameters.md`.
- **Dynamic** — emit two SQL files, the template and the `control_proc_code`; follow
  `references/dynamic_assignment.md` (and `references/sf_metamodel.md` for entities, naming,
  the `use_*` enable step, tags and the staging tables).

Run the result against the concept reference's checklist. Across all concepts:

- No `create`/`alter`, no declaration of the fixed/standard variables — use them as-is.
- Store the raw `db_value` for a column backed by a fixed value list. If the user names
  a value ("set status to Confirmed"), match `elemnt_id = Confirmed` in the metadata and
  use its `db_value`.
- `@` prefix for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
- Follow the **Thinkwise SQL formatting house style**: lower case only, leading commas,
  spaces not tabs, `begin`/`end` after every `if`/`while`, aligned aliases/joins/comparisons
  and `and`/`or`, column lists for inserts, and a short `--` comment after each domain value
  or literal. The full rules and canonical shapes are in `references/conventions.md`.

---

## Shared conventions

Cross-cutting helpers and rules live in `references/conventions.md`: the full
`tsf_send_message` reference (signature, `abort` semantics per dialect, XML parameters),
`tsf_user()` / `tsf_original_login()`, domain-element handling, control-procedure /
template naming, and the **SQL formatting house style** every fragment must follow. Read
that file whenever a fragment needs messaging, the username, or element handling, and always
apply its formatting rules to the emitted fragment; each concept reference also states what
is appropriate there (for example, a Default only ever uses `abort = 0`).

---

## Assignment references

Concept-independent references that govern how a fragment is packaged and assigned:

| Reference                          | Use when                                              |
|------------------------------------|-------------------------------------------------------|
| `references/parameters.md`         | the template uses `[bracket]` parameters              |
| `references/dynamic_assignment.md` | applying a template across many objects via SQL        |
| `references/sf_metamodel.md`       | any dynamic assignment (SF base model, staging, tags) |
