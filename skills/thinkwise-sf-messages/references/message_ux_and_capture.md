# Message UX, confirmations, and database error capture

Loaded on demand from `thinkwise_sf_messages`.

## UX principles for confirmations and choices

Two forces have to hold at once, and they pull against each other: **interrupt rarely** (a dialog
that fires on routine actions trains people to dismiss it without reading — and then they dismiss the
*next* one too, the one that mattered) and **when you do interrupt, be specific** ("Are you sure?"
gives the user nothing to check their intent against). Applying this to `msg`/`msg_option` design:

- **Label options by outcome, not Yes/No** — "Release anyway" / "Back to edit", not a bare Yes/No a
  user has to reconstruct meaning from. Already the convention for `msg_option` text (see "Best
  practices for option text" above); stated here as the general principle behind it.
- **Don't default to the dangerous answer.** Prefer no default at all; if the platform forces one,
  make the safe option the default and don't let the destructive option sit as the reflexive click.
- **For rare, genuinely catastrophic actions, require a deliberate act rather than a click.** A
  confirmation dialog becomes muscle memory the moment it's routine. For the few truly irreversible
  actions (wiping an environment, dropping a list), make the user do something they wouldn't do by
  reflex — e.g. type the object's name into a task parameter the task validates before proceeding.
  Reserve this for genuinely severe cases; using it everywhere just creates a new reflex.
- **Let an educational confirmation be switched off.** If a confirmation exists mainly to teach a
  feature's side effect the first few times, it should be dismissible so it doesn't graduate into
  permanent noise. Thinkwise has no built-in per-user "don't ask again," so treat this as a product
  decision to raise with the user, not a message-model feature to assume exists.

### When you can't infer severity/consequence, ask

Purpose and severity are almost always inferable from the request and the model — "add a confirmation
to the Delete Customer task" tells you the purpose, and the data model tells you the consequence (does
it cascade, how many dependent rows). Ask the user (the "Ask, don't default" convention from
`thinkwise_sf_base`, applied here) only when:

- **Whether the action is serious enough to interrupt at all isn't visible in the model** — is this
  "delete" a hard delete or a soft archive; is this "send" reversible?
- **The consequence itself isn't visible** — cascade depth, dependent-row count, what the user stands
  to lose. Guessing here produces exactly the vague dialog this section warns against.
- **The message branches and the branches' actual behavior isn't specified yet** — an
  affirmative/negative choice is meaningless until each outcome is known.

Ask the narrow factual question (the consequence, the severity, what each branch does), not "what
should the message say" — that's the writing, which follows once the facts are in hand.

## Task confirmation messages

A task can request confirmation before execution — verified fields on `task`: `ask_confirmation` (bool),
`confirmation_msg_id` (FK to `msg`), and `popup_for_each_row` (bool). Use confirmation for destructive,
expensive, broad, or externally visible actions — not as a substitute for a clearly named button.

**Include at least one parameter for context whenever practical.** A confirmation message with zero
parameters is flagged by a Software Factory validation — a generic "Are you sure?" that names nothing
specific about the record or action is exactly the vague text "Writing effective message text" above
warns against.

**`popup_for_each_row` is the modeled control for the bulk-confirmation anti-pattern** ("message storms"
in the failure patterns below) — when a task can run against multiple selected rows, decide deliberately
whether confirmation should fire once for the whole batch (`popup_for_each_row = false`, the usual
choice) or per row (`true`, rarely what you want — it's the mechanism behind the very message-storm
problem to avoid, so flip it on only when a genuinely per-row decision is required).

A dynamic confirmation (values filled in at runtime) is built by:
1. Adding task parameters for the values to display.
2. Filling those parameters in the task's Default control procedure.
3. Referencing them (via `<taskparam>`, see above) in the confirmation message's translation.

Good confirmation text identifies the action *and* consequence:

> Release order {0}? This will create {1} production jobs.

Weak confirmation text merely repeats the button ("Are you sure?"). Don't use confirmation when the
system can already determine the action is invalid — disable it or show an error instead. Ensure
keyboard focus and button labels make the safe choice clear.

## Database message capture

A modeled message can recognize a raw database engine error (unique index, foreign key, check
constraint, …) and replace it with localized business text, via `msg_error_code` +
`msg_regular_expression` + `priority` + named capture groups the translation can reference (e.g.
`{constraint}`).

Real verified examples from the base model (SQL Server), showing the actual named-group syntax and that
the framework's own generic captures sit at `priority = 100`:

```text
msg_id: mssql_error_duplicate_key_row       error_code: 2601   priority: 100
regex:  Cannot insert duplicate key row in object '(?<table>.+)' with unique index '(?<index>.+)'\.
        The duplicate key value is \((?<value>.+)\)\.

msg_id: mssql_error_check_constraint_insert  error_code: 547    priority: 100
regex:  The INSERT statement conflicted with the CHECK constraint "(?<constraint>.+)"\. The conflict
        occurred in database "(?<database>.+)", table "(?<table>.+)"(, column '(?<column>.+)')?\.
```

**A narrower, business-specific capture on the same error code needs a lower `priority` number than
100 to actually win** — e.g. `priority = 10` for a message translating the exact unique-index violation
on `customer.email` into "A customer with this email already exists," layered on top of (not replacing)
the generic `mssql_error_duplicate_key_row` catch-all. See `references/practical_examples.md` for a
worked version of this pattern.

### Recommended design

1. Keep the database constraint as the final integrity guarantee — don't remove it just because a nicer
   message now exists.
2. Where practical, validate earlier and present a contextual business error before the write is even
   attempted.
3. Add a capture message as the fallback for races, alternative write paths, and direct constraint
   failures the earlier validation didn't catch.
4. Match the narrowest stable signature available — prefer an exact error code plus a narrow expression
   over a broad catch-all.
5. Translate technical identifiers (constraint/index/table names) into user-recognizable business
   concepts; don't expose them raw just because they're available in a capture group.

### Regex guidance

- Anchor stable portions of the message where possible.
- Use named groups only for values that actually improve the user-facing message.
- Assign more specific patterns a lower priority number so they win over a generic base-model capture.
- Test against the actual database engine and version in use — error text differs across SQL Server
  versions and RDBMS platforms.
- Include near-miss error samples to prove the expression doesn't capture unrelated faults.
- Recheck patterns after a database-platform upgrade or a localization change to the engine's own error
  text.

## Messages by logic concept

- **Defaults and layouts** — these fire frequently, sometimes mid-typing. Avoid popups from routine
  default/layout evaluation; use validation state, field visibility, mandatory state, or task-button
  state instead. If an informational message is essential here, make sure it can't repeat on every
  refresh.
- **Tasks and subroutines** — a natural place for completion, validation, and integration messages. A
  reusable subroutine (`thinkwise_sf_subroutines`) should normally return a structured
  result to its caller and emit a user message only when its contract explicitly owns presentation — a
  subroutine that always pops a message becomes hard to reuse from an API, a job, or a process flow.
- **Triggers and handlers** — use messages here for database-enforced failures that must stay consistent
  across every write path. Keep wording business-oriented, roll back deliberately, and support
  multi-row operations — never one message per affected row.
- **Process logic** — prefer the standard modeled message mechanism and predictable abort behavior for
  errors returned from CRUD processing; make sure the message actually corresponds to the transaction
  outcome.
- **Process flows** — use **Show message** for presentation and branching (see above); keep the real
  technical work in tasks/subroutines and let the flow coordinate the interaction.

## API, offline, and unattended behavior

A Thinkwise application isn't always driven through a GUI — the same logic can run through Indicium
APIs, scheduled work, process flows, or offline sync.

- Never make correctness depend on a user clicking a popup.
- Return a stable error condition and a suitable HTTP/process outcome for aborting errors.
- Assume information/warning presentation differs by client.
- Never require an interactive confirmation on an unattended execution path.
- Separate a machine-readable result from the localized user-facing text where an integration needs to
  react programmatically — don't make a caller parse translated prose to determine the error type.
- Test the actual Indicium response, not only the Universal UI rendering.
