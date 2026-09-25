# Translation naming, plural forms, and help text

Loaded on demand from `thinkwise_sf_translations`.

## Naming — the object ID *is* the translation key

Because `task_transl_selected_objects` ("translate by ID") derives a label straight from
`transl_object_id`, a well-named object is half-translated before anyone types anything —
`sales_order_line_status` becomes "Sales order line status" for free.

**Gotcha: `transl_object_id` for a column is the bare column ID — not qualified by
table.** Querying the real `INSIGHTS` model for `col` rows with `col_id eq 'description'` returns ten
different tables (`activity`, `country`, `declaration`, `declaration_lines`, `employee_function`,
`employee_item`, `hour`, `hours_with_customer`, `meeting`, `project`, …) all sharing that column name.
Querying `transl_object_transl` for `type_of_object eq 1 and transl_object_id eq 'description'`
returns exactly **one** row per language — meaning all ten tables' `description` columns render the
same translated text, and editing any one of them changes it everywhere at once. This is by design
when the columns really do mean the same thing (a generic "description" field genuinely should read
identically everywhere) — but it's a live trap the moment two same-named columns need to diverge.

Two fixes, confirmed against the platform's own translation model:

- **Rename the column** so its ID is specific to what it actually holds (`loon_component_code`
  instead of a bare `code` reused elsewhere with different meaning) — the default choice, and it also
  sits well with `task_transl_selected_objects` auto-deriving a better label for free.
- **Point `col.alt_transl_col_id` at a different column's ID** to deliberately *share* a translation
  with something else, or add a genuinely new column and translate it independently, if the source
  column must keep its generic ID for another reason (e.g. it's shared through a domain on purpose).

**Domain elements** (`type_of_object = dom_elemnt`, value 2): the `transl_object_id` is the element's
own ID. Real IDs pulled live from `INSIGHTS` include both plain descriptive IDs (`approved`,
`approve_working_hours`) and numeric-prefixed ones (`1_project`, `2_customer`) — the latter pattern
sacrifices some of the "ID carries all descriptive meaning, database value stays a meaningless
sequential integer" convention (see the `thinkwise_sf_data_model` skill's Domain elements
section) for explicit, stable ordering. Match whatever convention the model already uses rather than
mixing both within one domain.

## Avoid the literal word "ID" in translated text

Translated labels (`transl`/`transl_form`/`transl_grid`/`transl_card_list`/…) should read as natural
language for an end user, not restate the database naming convention. An object like `employee_id`
should normally translate to "Employee", not "Employee ID" — the underlying column name already
encodes that it's an identifier; the label doesn't need to repeat it. Only keep "ID" in the
translated text when it's genuinely the only unambiguous option — e.g. an external reference number
where "ID" (or a more specific term like "order number") is the actual meaning being conveyed, or a
screen that shows a name and a numeric identifier side by side and needs the second one distinguished
from the first.

## Plural forms — authored per language, not derived

`transl_plural` is its own field, filled independently per `appl_lang_id` — the live `activity`
example above shows eight different, grammatically-correct plural strings (`Aktivitäten`,
`Activities`, `Actividades`, `Activités`, `Attività`, `アクティビティ`, `Activiteiten`, `Atividades`),
none of which the platform derived from `transl`. Where it's used: list/detail tab headers, card list
headers — anywhere the UI names a collection of rows rather than one row.

**Link tables shown as a detail tab get a directional plural.** Per platform docs: write
`transl_plural` as `singular/plural` (e.g. `Persons/Companies` for a person↔company link table) — the
UI shows the second half when the tab is opened from the "singular" side (a person's record shows a
"Companies" tab) and the first half from the other side (a company's record shows a "Persons" tab).

Because pluralization grammar differs per language (English's irregular plurals, German/Dutch
compounding, gendered agreement in French/Spanish/Portuguese/Italian), a plural correct in one
language says nothing about another. If `task_enrichment_auto_transl` (AI) is used to backfill a
plural into a new language, treat it as a draft, not a commit — review it before approving, same as
any other AI-drafted translation.

**Verify after a combined write:** another instance of the general "a multi-field
write can silently drop one field" behavior in `thinkwise_sf_data_model`'s quirks section —
setting `transl` and `transl_plural` together in one write occasionally left `transl_plural` reverted
back to equal the just-set singular `transl` instead of the plural value that was also specified in
the same write — reproducible on 2 of 6 table records in one session, not a one-off typo. Re-read the
field back after this kind of combined write and re-apply `transl_plural` if it doesn't match before
committing; don't assume a multi-field write that returned success actually applied every field as
given. **Re-tested and fixed**: setting `transl_plural` *after* `transl` in the same
combined call avoided the revert entirely — both fields held correctly with no follow-up patch needed.
Order the properties this way instead of budgeting for a second corrective write.

## Help text — leave `approval_status` review aside, default to empty

`help_text` is a distinct, longer-form field tied to Help screens — not a longer tooltip. The live
`activity` example makes the real cost concrete: `help_text` is filled with a genuine, well-written
definition-plus-example for exactly **two of the eight configured languages** (`en-US`, `nl-NL`); the
other six (`de-DE`, `es-ES`, `fr-FR`, `it-IT`, `ja-JP`, `pt-BR`) simply have none. That's not
necessarily a bug — it may be a deliberate call that only two languages' user bases need the extra
explanation — but it is exactly the failure mode to design against: **every `help_text` filled in one
language is an implicit promise to either fill it in every other configured language, or accept that
most of your users never see it.**

**Convention: leave `help_text` empty by default.** Reach for it only when a field's behavior is
genuinely non-obvious — a calculation the label can't convey, a workaround, a non-obvious
precondition. A clear object name (see Naming above) plus a short `tooltip_text` covers the large
majority of fields. Before filling in `help_text` for a new object, either commit to authoring it for
every language the branch has configured (query `branch_appl_lang` to know how many that is — see
below) or flag to the user that it will be English/source-language-only for now.
