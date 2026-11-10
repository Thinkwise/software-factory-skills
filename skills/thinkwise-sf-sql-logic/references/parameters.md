# Template parameters

Parameters make a template reusable across program objects. They are placeholders in the
template code, written in **square brackets**, that get one or more values per assignment.
The SF auto-creates a parameter on the template's Parameters tab for every distinct
bracket name it finds in the code.

## Syntax

- A parameter is `[name]`. It substitutes as literal text, including *inside* an identifier:
  `@[active_col]` -> `@active`, `'[active_col]'` -> `'active'`, `@[from_col]` -> `@active_from`.
- Choose descriptive names (`[active_col]`, `[from_col]`), not the concrete column names.

## Value behaviour (know these three rules)

1. **Single value** — the placeholder is replaced by the value, everywhere it appears.
2. **Multiple values** — the *line* containing the parameter is repeated once per value.
   One template line becomes N lines. Use this to fan a statement out over several columns.
3. **Empty value + "Ignore if empty"** (`no_line_when_empty = 1`) — the line containing the
   parameter is not included in the end product. This is the documented behaviour; the docs
   do not specify what an empty value does *without* the flag, so do not rely on that case —
   either give the parameter a value or set the flag.

## Static vs dynamic

- **Static assignment** — the developer assigns the template to program object items and
  fills the values by hand. The values live in `prog_object_item_parmtr` per item. Assigning
  to a disabled concept via the Assigning tab enables that concept automatically.
- **Dynamic assignment** — the `control_proc_code` supplies the values (see
  `dynamic_assignment.md`). Same parameter mechanism, values computed at generation time.

## Output for a STATIC, parameterized assignment

Deliver two things:

1. The **source-code template** — the fragment with `[bracket]` placeholders.
2. A **parameter overview** — per program object item, the parameter values assigned.
   This is a table, not SQL, because the same template gets different values per item:

   | Program object     | Program object item        | [active_col] | [from_col]    |
   |--------------------|----------------------------|--------------|---------------|
   | `default_order`    | `fill_active_from_order`   | `active`     | `active_from` |
   | `default_customer` | `fill_active_from_customer`| `is_active`  | `valid_from`  |

   Add a "no_line_when_empty" note per parameter only when a value is intentionally left
   empty to suppress a line.

If the concept template has **no** parameters, this file does not apply: deliver the plain
fragment as usual (base skill behaviour).
