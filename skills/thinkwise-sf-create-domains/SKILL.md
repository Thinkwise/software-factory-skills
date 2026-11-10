---
name: thinkwise-sf-create-domains
description: >-
  Create domains (dom) and their elements (elemnt) in the Thinkwise Software
  Factory through the legacy, unofficial sf-mcp-server connector
  (create_entity / query_entities) only. With an Indicium MCP connector
  (stage_resource / commit_resource) use thinkwise-sf-data-model
  (references/domains_and_elements.md) instead. On the legacy connector, use
  this skill when the user wants to add/import domains, data types, value lists,
  combobox values or elements into a Thinkwise SF model — for example "add these
  domains to the LANSA model" ("voeg deze domeinen toe aan het LANSA-model"),
  "create a domain in the MAIN branch" ("maak een domein aan in de MAIN
  branch"), "import the domains via the MCP" ("importeer de domeinen via de
  MCP"), "add the elements too" ("zet de elementen erbij"), or a bulk import of
  a generated payload; also when unsure which fields to pass to create_entity
  for dom/elemnt, which dttp_id is valid for SQL Server, or why a create is
  rejected (403). model_id and branch_id are always parameters.
---

# Thinkwise SF — creating domains & elements via MCP

## Scope `(legacy sf-mcp-server)`

This skill is for the legacy, unofficial **sf-mcp-server** connector: direct OData creates with
`create_entity`/`query_entities`, no staging. With an **Indicium MCP** connector (`stage_resource`/
`patch_resource`/`commit_resource`), use `thinkwise-sf-data-model` and its
`references/domains_and_elements.md` instead. The mapping for Indicium MCP users:

| Here (legacy) | Indicium MCP |
|---|---|
| `create_entity` on `dom` with `model_id`/`branch_id` in the data | add `dom` **under its parent `branch`** (parent key `model_id`, `branch_id`) |
| `create_entity` on `elemnt` with `dom_id` in the data | add `elemnt` **under its parent `dom`** |
| `prog_lang_id` on `dom` | not sent — refused as `unknown_property` on SF 2026.2 (`dom` carries `rdbms_type`, set by the branch) |
| one call per record | stage → patch → commit per record, under `thinkwise-sf-base`'s write rules |

Field names (`dttp_id`, `length`, `prec`, `dom_description`, `control_id`, `elemnt_id`, `db_value`,
`order_no`, `available`) and the `control_id`-after-`dttp_id` order carry over to both.

This skill covers the **MCP part**: exactly which fields you pass to
`mcp__sf-mcp-server__create_entity`, what you get back, and the pitfalls that
cause 403s in practice. Building/consolidating the payload itself is out of
scope — this is about the write action to the Software Factory.

`model_id` and `branch_id` are **always** parameters. Ask for them or derive them;
never assume a fixed value. The examples use `LANSA`/`MAIN` purely as
illustration.

## 0. Load schemas

The MCP tools are deferred. Load them first:

```
ToolSearch: select:mcp__sf-mcp-server__create_entity,mcp__sf-mcp-server__query_entities
```

## 1. Check what already exists first (resumability)

Importing is often a bulk action that can stop halfway (tokens run out, rejected
calls). So make it **idempotent**: query the existing `dom_id`s and create only
the difference.

```
query_entities
  entity_set: dom
  filter: model_id eq '<MODEL>' and branch_id eq '<BRANCH>'
  select: dom_id
  top: 250        # set high enough; default is 20
```

Filter your payload list against this set before you start. Do the same for
`elemnt` when you resume elements.

## 2. Creating a domain (`dom`)

```
create_entity
  entity_set: dom
  data: {
    "model_id":       "<MODEL>",
    "branch_id":      "<BRANCH>",
    "dom_id":         "kosten_status",        // lowercase_underscore, unique within model+branch
    "prog_lang_id":   "SQL",
    "dttp_id":        "NUMERIC",              // see §4 for valid values
    "dom_description":"Kosten Status — ...",  // NOTE: dom_description, not description
    "length":         3,                       // numeric: precision; text: length
    "prec":           0                        // numeric: scale (decimals); omit for text
  }
```

Field by field:

| Field | Required | Notes |
|---|---|---|
| `model_id`, `branch_id` | ✅ | Parameters. |
| `dom_id` | ✅ | Identifier, unique within model+branch. Lowercase, underscores. |
| `prog_lang_id` | ✅ | `"SQL"` for SQL Server models. |
| `dttp_id` | ✅ | Data type id. **SQL Server: `NUMERIC`, not `DECIMAL`** (DECIMAL does not exist in the dtp table → 403). See §4. |
| `dom_description` | ✅* | The description field is called **`dom_description`** (not `description`). Use it to record the origin/dictionary name. |
| `length` | numeric/text | For numeric = **precision** (total number of digits). For VARCHAR = length. |
| `prec` | numeric | = **scale** (number of decimals). Omit for text/integer without decimals. |
| `control_id` | ✅ after `dttp_id` | Verified on a create (`EMAIL`, and the upload controls `IMAGE_UPLOAD`/`FILE_UPLOAD`). Send it after `dttp_id`; see §5. |
| `dttp` | ❌ never | **Computed field.** Passing it → 403. Always use `dttp_id`. |
| `rdbms_type` | ❌ never | Not editable; the branch determines it. |
| `min_value`, `max_value` | optional | Strings, also for a numeric domain (`"0"`, `"100"`). |

\* `dom_description` is functionally required in our workflow (to record the origin),
even though the API technically sometimes accepts a domain without one.

A domain has no translation object of its own — only its elements (and the columns using it) do.

**Success response:**
```json
{ "status": "success",
  "location": "iam/sf/dom(model_id='LANSA',branch_id='MAIN',dom_id='kosten_status')" }
```

## 3. Creating elements (`elemnt`) — value lists / comboboxes

Elements are the fixed values of a domain (e.g. status codes, yes/no, day codes).
Create them **only after all domains exist** — `elemnt` has an FK to `dom`.

```
create_entity
  entity_set: elemnt
  data: {
    "model_id":  "<MODEL>",
    "branch_id": "<BRANCH>",
    "dom_id":    "soort_mutatie",   // must already exist
    "elemnt_id": "Credit",          // identifier/name of the element
    "db_value":  "C",               // the value as stored in the database
    "order_no":  10,                // order; use 10,20,30,... to leave room
    "available": true
  }
```

| Field | Notes |
|---|---|
| `dom_id` | The domain this element belongs to (must exist). |
| `elemnt_id` | Identifier of the element (often a readable name or the code itself). It is also the element's translation key, shared by every element with the same id in the model — give a generic id (`open`, `yes`, `active`) a distinguishing prefix (`order_status_open`) unless that shared label is intended. |
| `db_value` | The value actually stored. May differ from `elemnt_id` (e.g. `+90`, `*Z03_FIS_BKH`). |
| `order_no` | Sort order. 10/20/30 leaves room to insert values later. |
| `available` | `true` = available as a choice. |

**Success response:** `location: iam/sf/elemnt(...,dom_id='soort_mutatie',elemnt_id='Credit')`

## 4. Determining valid `dttp_id` values

The valid data type ids depend on `prog_lang_id`. Unsure? Query the `dttp` set:

```
query_entities  entity_set: dttp   top: 100
```

Common for **SQL Server** (`prog_lang_id="SQL"`):

| Source type | `dttp_id` | length | prec |
|---|---|---|---|
| Decimal/amount | `NUMERIC` | precision | scale (decimals) |
| Integer / surrogate key | `INT` (or `BIGINT`) | — | — |
| Alphanumeric | `NVARCHAR` | length | — |
| Date | `DATE` | — | — |

These follow `thinkwise-sf-data-model`'s data-type recommendations (`references/domains_and_elements.md`);
where they differ from a payload you were handed, ask before converting. Check every `dttp_id` against
the `dttp` query above — the set differs per branch.

> ⚠️ `DECIMAL` does **not** exist in the SQL Server dtp table — use `NUMERIC`.
> For SQL Server, `length` = precision and `prec` = scale.

**PostgreSQL** (branch `rdbms_type` 4) has its own set of `dttp_id`s: `BIGINT`, `BOOLEAN`, `BYTEA`,
`CHAR`, `DATE`, `DOUBLE_PRECISION`, `INT`, `JSON`, `JSONB`, `NUMERIC`, `REAL`, `SMALLINT`, `TEXT`,
`TIME`, `TIMESTAMP`, `UUID`, `VARCHAR`, `XML`. There is no `DECIMAL`, `DATETIME`, or `BIT` — use
`NUMERIC`, `TIMESTAMP`, and `BOOLEAN`. `NUMERIC(p,s)` is again `length` p, `prec` s.

On every platform:
- Send `length`/`prec` only where the data type defines them (e.g. not for `INT`, `DATE`, `BOOLEAN`).
- Use the `_MAX` type for unlimited text or binary data; a `VARBINARY` without a length stopped
  definition generation.

## 5. `control_id` (combobox etc.)

Send `control_id` after `dttp_id` on the create (verified with `EMAIL`; the control ids `EMAIL`,
`PHONE_NUMBER`, `URL`, `IMAGE_UPLOAD` and `FILE_UPLOAD` are global, not per model). A create has been
seen refused with `{"error":"Patch of field 'control_id' failed: ","http_status":403}`, likely with
the field sent before the data type; if that happens, set it with an edit afterwards.

Tell the user when domains were supposed to get a combobox, so the choice is a deliberate one.

**Email, phone, and web address domains** get control `EMAIL`, `PHONE_NUMBER`, or `URL`.

**Upload domains** — an upload is two columns on two domains:
- the file-name column's domain: text (`VARCHAR`/`NVARCHAR` 255) with control `IMAGE_UPLOAD` or
  `FILE_UPLOAD` and a `file_storage_id`. `file_storage_id` is editable, and mandatory, only while an
  upload control is set: send `control_id` first, then `file_storage_id`. To remove the control,
  clear `file_storage_id` first, then `control_id`. The column on it sets `data_col_id` to the
  storage column;
- the storage column's domain: binary `_MAX` (`VARBINARY(MAX)`, `BYTEA` on PostgreSQL) **without** a
  control. Never put the upload control on the binary domain — the Software Factory then requires a
  storage column for every column of that domain.

Every file storage needs `file_storage_extension_whitelist` rows, stored with the dot (`.png`), or
validation reports `val_file_extension_whitelist_empty`.

## 6. Batching & workflow `(legacy sf-mcp-server)`

On an Indicium MCP connector these rules don't apply — follow `thinkwise-sf-base`'s write rules
(staging several self-contained records per message, re-reading each before its commit).

- Make ~**10 `create_entity` calls in parallel** in one turn (independent calls). Many more than ~10
  at once makes error diagnosis harder.
- Order: **all domains first, then all elements.**
- Report progress as a counter (`30/119 ✓`) so resuming is easy.
- On a rejected call: correct it (see the pitfalls) and retry only that one call —
  do not invent a new payload for the rest.

## 7. Windows / encoding pitfall

If you read your payloads from a JSON file on Windows, read it explicitly as UTF-8,
otherwise an em dash `—` turns into mojibake (`â€"`):

```powershell
$content = [System.IO.File]::ReadAllText('<path>\sf_payload.json', [System.Text.Encoding]::UTF8)
$data = $content | ConvertFrom-Json
```

In the `data` of `create_entity`, pass non-ASCII characters as JSON unicode escapes,
e.g. an em dash as `\u2014`, to prevent them from being mangled in transit.

## Quick checklist

1. `ToolSearch` → load the tools.
2. `query_entities dom` → what already exists? Filter the payload.
3. Per domain `create_entity dom`: `model_id`, `branch_id`, `dom_id`, `prog_lang_id`,
   `dttp_id`, `dom_description`, `length`, (`prec`), then `control_id` if any. **No** `dttp`,
   **no** `rdbms_type`.
4. SQL Server: `NUMERIC` (not DECIMAL), `length`=precision, `prec`=scale. PostgreSQL: see §4.
5. All domains done? → `create_entity elemnt` per element (`dom_id`, `elemnt_id`,
   `db_value`, `order_no`, `available`).
6. Controls: `control_id` goes after `dttp_id` in the create (§5); report which domains got a combobox.
