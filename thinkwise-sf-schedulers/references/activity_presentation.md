# Scheduler activity presentation — conditional layout and HTML formatting

Loaded on demand from `thinkwise_sf_schedulers`.

## Conditional layout — activities

An ordinary `conditional_layout` row on the Scheduler's subject, scoped to a column (e.g. status) — no
separate "activity colour" concept. Set `show_conditional_layout = true`, pick the column (blank =
whole row), configure background/font colour per theme plus bold/italic/underline/strikethrough and
size, then add `conditional_layout_condition` rows. For the full field reference, condition enum, and
known gaps/pitfalls of this entity family, see `thinkwise_sf_conditional_layouts` — this
section only covers what's Scheduler-specific (the HTML interaction below, and the resource variant
next).

**Don't combine with HTML formatting** — if the title/tooltip column has HTML/Multiline control turned
on, conditional layout is ignored for that activity, and specifically font-size/strikethrough/underline
are ignored even in mixed setups. Do all styling inline in the HTML/CSS once you're in HTML territory.
This is exactly why the reference model still keeps one plain conditional layout around (`text_white`,
on `title`, white background both themes, `apply_to_scheduler_resource = false`) — as a fallback for
the one activity display type (below) that opts *out* of HTML.

## Conditional layout — resources

Same mechanism, plus the `apply_to_scheduler_resource` checkbox — colours the resource's row/label in
the grouping panel rather than an activity bar. Typical use: grey out an unavailable resource, tint
parent vs. child rows in a hierarchy. **Evaluation rule**: only the first matching record per resource
decides which layout applies — design conditions assuming "first match wins."

**Don't** expect this to apply alongside HTML-formatted activities/tooltips — mutually exclusive in
practice, same as above.

**Known gap**: no native resource capacity/availability concept to colour against (unlike the old
extender's Worktime table). Workaround: synthetic "off-duty" activities styled distinctly, or a
time-cell condition off explicit hour columns. The reference model's `number_of_hours_available`/
`number_of_hours_planned` columns are exactly the kind of data you'd condition on — in that model
they're randomly generated demo placeholders (`cast((abs(checksum(newid)) % 13) + 5 as int)`), not a
working capacity engine; in production these would come from a real rostering/availability source.

## HTML and multiline activity formatting

### Ask before building: what should an activity look like?

Before setting a control type on the title/tooltip column, ask the user directly (`AskUserQuestion`)
how they want an activity to render — don't default to HTML just because it's the richest option:

- **Single line** — plain text, one line, no wrapping. Domain control type stays plain/default.
- **Multiline** — plain text with line breaks, domain control type `MULTILINE`. Good for a title plus
  a short subtitle with no colour/styling need. `PROJECT_MANAGER`'s tooltip column
  (`description`) uses domain `scheduler_tooltip`, control `MULTILINE`, plain text.
- **HTML** — rich formatting (colour swatches, badges, progress bars, cards), domain control type
  `HTML`, backed by a calculated column building an HTML string with `concat`. `PROJECT_MANAGER`'s `title` column uses domain `title_html`, control `HTML`. Remember this also
  silences conditional layout on that column (font-size/strikethrough/underline specifically) — see
  "Don't combine with HTML formatting" above.

**If HTML is chosen, ask a follow-up** on which display style to use — present the verified styles
below from the reference model's 10-element `activity_display_type` dispatcher domain (see "The
dispatcher pattern" in `references/html_activity_formatting.md` for the SQL behind each) rather than
leaving the user to invent one from scratch:

| Style | Looks like | Best for |
|---|---|---|
| `outlook_second_line` | Bold title, italic subtitle line underneath | Title + secondary detail, no colour coding needed |
| `status_round` | Filled circle swatch + title | Compact status colour cue |
| `status_rounded_rectangle` | Rounded-square swatch + title | Same cue, slightly more visible swatch — **recommended default** |
| `status_slim_bar` | Thin vertical colour bar + title | Mimicking Outlook/Google Calendar's colour-strip convention |
| `status_outlined` | Outlined circle (border colour only) + title | Status cue without implying a solid/committed state (e.g. "tentative") |
| `pill` | Title + small rounded badge | A flag/count/label that needs extra emphasis (e.g. "!") |
| `progress_bar` | Title + percentage slider below | Progress/completion tracking |
| `activity_card` | Multi-line card: eyebrow label, title, avatar + name | Rich detail when cell height allows it |
| `activity_card_compact` | Same card, no avatar row | Rich detail in tighter cells |
| `none` | Plain title, no HTML wrapper | Opting out of HTML for this activity — pair with an ordinary conditional layout instead |

**Recommendation**: default to `status_rounded_rectangle` when the user has no strong preference — it
reads clearly at any cell width or zoom level, conveys a status colour without needing the extra row
height a card needs, and reuses the same `activity_status_color` computation as most of the other
styles (only `progress_bar` and `activity_card`/`_compact` need columns beyond that). Reach for
`status_slim_bar` instead when the user specifically wants the Outlook/Google-Calendar colour-strip
look, `pill` when there's a count/flag to surface, and `activity_card`/`_compact` when the Scheduler's
row height is generous enough for multi-line content.

Once the format (and, for HTML, the display style) is confirmed, proceed with the mechanics below.

For the dispatcher pattern that drives HTML activity layouts from a domain column (status colour,
progress bar, activity cards, pill badges, tooltip emoji/unicode, and height management to stop tall
HTML content from blowing out row height), read `references/html_activity_formatting.md` before
implementing.
