---
name: thinkwise-sf-messages
description: Reference guide for creating and maintaining modeled user-facing messages in a Thinkwise Software Factory model — errors, warnings, confirmations, process-flow choices, progress text, and translated database errors. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a message, or before writing a message-calling SQL statement or a database-error-capture regex.
---

# Creating and Maintaining Messages in the Thinkwise Software Factory

Reference for the full message lifecycle: `msg` (master object) → `msg_option` (choice messages only) →
translation (one `transl_object_transl` row per application language) → wired into SQL
(`tsf_send_message`/`tsf_send_progress`), a task's confirmation setting, a process flow's **Show
message** action, or a database-error-capture rule. Domain: split-domain instances `sf/manage_messages`
(holds `msg`, `msg_option`, `audio_file`, plus read access to `transl_object_transl`/`process_action`/
`task`/`icon` for usage look-ups); single-domain `sf/software_development`; otherwise find it with
`search_domain_capabilities`.

## What a modeled message is, and what it isn't

A modeled message is a reusable contract between business logic and the UI: logic emits a stable
`msg_id` plus optional parameters; the runtime resolves translation, presentation, severity, and
behavior. It is **not** the same thing as:

- Application-domain records such as inbox messages, chat messages, or notifications — those are
  ordinary tables in your data model, not `msg`.
- Software Factory validation findings (`validation_msg`) — the modeler's own lint output, unrelated.
- Message-broker payloads (`message_broker`/`message_broker_message`, MQTT etc.) — integration data on
  the wire, not UI text. See `thinkwise-sf-message-brokers`.
- Server logs and technical diagnostics not modeled under **User interface > Messages** — use
  structured server-side logging for those instead.

```text
Business logic / process flow / database error
                    |
                    v
          msg_id + parameter XML
                    |
                    v
     msg row + active-language translation
                    |
                    v
       Popup, panel/snackbar, debug, or suppress
```

## Entity map

| Entity | Key (adds to parent) | Purpose |
|---|---|---|
| `msg` | `msg_id` | Master object: location, severity, database-capture config, audio |
| `msg_option` | `msg_option_id` | One row per choice on a **Show message** process action |
| `audio_file` *(read-only)* | `audio_file_id` | Uploaded `.wav`/`.mp3` assets — uploaded elsewhere (Software Factory file/theme management), only referenced here |

`msg` and `msg_option` are both writable (`allow_add/update/delete = true`) with no creation-order
gate. Add a `msg` under its `branch` (`parent_entity_set` `branch`) — a bare add is refused. Stage a
`msg_option` the same way, under its `msg`, if its bare add is refused.

### `msg` fields

`msg_description` (developer-facing, not shown to users), `msg_location_id` (**string** enum — the
column literally holds `"popup"`/`"panel"`/`"suppress"`/`"debug"`, not a numeric code), `severity`
(**byte** enum: `error` 0, `warning` 1, `information` 2 — don't confuse this with the *database*
severity levels 9/16 mentioned under "Abort behavior" below, which are a SQL Server engine concept,
unrelated to this field), `msg_error_code`, `msg_regular_expression`, `priority` (byte — lower number
wins when multiple capture rules match), `audio_file_id`, `generated_by_control_proc_id`.
`priority` is read-only until `msg_regular_expression` has a value, then editable and mandatory —
send the regex before the priority in the same write (verified through the write API on SF 2026.2).

### `msg_option` fields

`response_type` (**bool flag** — `true` = affirmative, `false` = negative),
`msg_option_status_code` (int32, **read-only** — derived from `response_type`, see below), `icon_id`/`icon`, `order_no`.
Set `icon_id` to a suitable icon per `thinkwise-sf-icons` as part of creating each
option — reinforce the outcome (Continue → check/arrow-forward, Retry → retry arrow, Cancel → X) rather
than leaving it unset, and keep affirmative/negative icons visually distinct from each other.
Send `icon_id` as the raw integer `icon.icon_id` (`value_kind: "data"`; look it up with
`icon?$select=icon_id,icon_title`, e.g. `icon_title = 'check'` → `11835` — the title string itself gives
`invalid_input`) and read it back: it has been both accepted and
refused with `403` on the same Software Factory version. On a refusal, a plain value resolves through
the icon look-up's display column, which can pick a different icon than the id you meant — read
`icon_id` back after that write too, and fall back to setting it in the Software Factory.

**Status-code convention, verified against the base model's own confirmation messages**: affirmative
options (`response_type = true`) get status codes `0`, `1`, `2`, … in ascending order; negative options
(`response_type = false`) get `-1`, `-2`, `-3`, … Real example (`confirm_set_branch_close_all_documents`):
`no` → `response_type=false, status_code=-1`; `yes` → `response_type=true, status_code=0`; `yes_always`
→ `response_type=true, status_code=1`.

**You don't set the status code — the Software Factory derives it from `response_type`.** Verified
through the write API on SF 2026.2: `msg_option_status_code` is read-only; `response_type = true` gives
`0`, `false` gives `-1`; further options of the same kind are reported to get `1`, `2`, … / `-2`, … in
add order. Sending the status code fails with `field_not_editable` and stops the rest of the write (see
`thinkwise-sf-base`). So control the numbering through `response_type` and the order you add the options
in — a process flow branching on the numeric status code (see "Wiring into a process flow" below)
depends on it being predictable; read the codes back after the add.

## Choosing severity and location

| Situation | Severity | Location | Abort? |
|---|---|---|---|
| The requested operation is invalid | Error | Popup | Yes |
| The operation is valid but risky | Warning | Popup | Usually no, or ask confirmation first |
| The action completed successfully | Information | Panel/snackbar | No |
| The user must choose how a process continues | Information or warning | Popup with `msg_option`s | Controlled by the selected status code |
| Long-running task progress | Information | Progress display (`tsf_send_progress`) | No |
| Raw database constraint error | Usually error | Popup after capture | Yes |
| Expected noisy database message | Any | Suppress | Depends on the original action |
| Developer-only diagnostic | Information | Debug/log | No |

**Error** — use when the change/operation cannot safely complete; Thinkwise documents that only error
severity cancels the action at the platform level. Say what could not be done, why in business
language, and what the user can change next. Never expose SQL, table/constraint names, stack traces,
credentials, endpoints, or personal data — keep those in secured logs with a correlation id.

**Warning** — the action is allowed but has an unusual/harmful/irreversible consequence, and the warning
must support a real decision. If the condition actually makes execution invalid, that's an error, not a
warning. If there's no meaningful choice, use information instead of forcing an acknowledgement.

**Information** — successful completion, useful status, or neutral explanation. Prefer panel/snackbar
for short-lived feedback; reserve popup for information that must be read before continuing. Avoid a
success message after every ordinary save — the updated screen state is usually confirmation enough.

## Message location

- **Popup** — blocking errors, important warnings, confirmations, process-flow choices. Reserve for
  what genuinely needs attention; popups interrupt work.
- **Panel/snackbar** — bottom-of-screen in the legacy Windows GUI, a snackbar in Universal UI.
  Non-blocking feedback, status updates, sequences of related messages. Two reserved messages manage
  panel output from code in the base model (`add_separator`, `msg_location_id='panel'`,
  "insert a separator between previous and new panel messages"; `clear_panel`, same location, "clear
  the previous messages") — Thinkwise explicitly advises using these only from code, never as a task
  confirmation message or a Show message process action.
- **Suppress** — a known database message that should not reach the user. Changes presentation only,
  not correctness — document *why* it's safe, since suppression can turn a visible defect into an
  unexplained silent failure.
- **Debug** — primarily a legacy-client facility; prefer structured server-side logging with
  correlation ids for current production apps. Never depend on a debug message for essential guidance.

**Audio** — `.wav`/`.mp3` on popup/panel messages via `msg.audio_file_id` (references an existing,
separately-uploaded `audio_file` row — `audio_file` is read-only through the connector). Use only where visual attention
is insufficient (hands-busy shop floor, a safety alert); always pair with a visual equivalent and
respect shared workspaces/accessibility.

## Plan first

Applies `thinkwise-sf-base`'s "Confirm-before-mutate" convention (see its Shared
conventions section) to a message — don't restate that rule, apply it. Before the first
`stage_resource`/`stage_task` call that creates a `msg`, `msg_option`, or translation row, present the
user with:

- The proposed **severity**, **location**, and **abort behavior** — the decision step 1's table below
  leads to, stated as a concrete recommendation rather than left implicit.
- The **drafted message text**, including its parameters in order (see "Writing effective message
  text" and "Parameters and translated text" below for how to draft it) — and, if this is a choice
  message, the drafted `msg_option` labels and status codes too.

Get explicit confirmation on that package before creating anything. If the answer changes the
severity/location/abort choice or the text itself, re-confirm the updated version rather than staging
the original draft.

## Step-by-step: creating a message

1. Decide severity, location, and abort behavior first — everything else follows from that (use the
   table above). This is the decision "Plan first" above presents to the user before step 2 creates
   anything.
2. **Create the `msg` row**: purpose-based `msg_id` (see "Naming and reuse" below), `msg_description`
   for developers, `msg_location_id`, `severity`. Leave `msg_error_code`/`msg_regular_expression`/
   `priority` unset unless this is a database-capture message (see below).
3. **Write the source-language translation.** A `msg` is a translation object (`type_of_object = 4`) — its translated text lives in `transl_object_transl`, one row per application
   language, matched on `(type_of_object=4, transl_object_id=<msg_id>, appl_lang_id)`. Follow
   `thinkwise-sf-translations`'s generic workflow for finding/overwriting the
   `[bracketed]`-placeholder row rather than adding a new one — this skill only adds the `msg`-specific
   fact that its `type_of_object` is `4` and its live text field is `transl`.
4. **If this is a choice message (Show message with options)**, add `msg_option` rows — see "Message
   options" below, including the shared-translation gotcha before you name a new option.
5. **Add every other application-language translation** and get each reviewed.
6. **Wire the caller** — SQL (`tsf_send_message`), a task's confirmation setting, a process flow's Show
   message action, or a database-capture rule. See the sections below for each.
7. **Copy/rename/delete** via the bound tasks on `msg`, verified: `task_copy_msg` (`from_msg_id`,
   `to_msg_id`), `task_rename_msg` (`branch_id`, `from_msg_id`, `to_msg_id`), `task_delete_msg`
   (`branch_id`, `msg_id`). Prefer these over hand-duplicating a message. A deleted message (or
   option) leaves its `transl_object` rows behind — delete them afterwards (see
   `thinkwise-sf-translations`).
8. **Before renaming/deleting/changing placeholders on an existing message**, check its usage —
   `msg`'s navigation properties `detail_ref_msg_process_action` (process actions using it),
   `detail_ref_msg_task` (tasks using it as a confirmation message), and
   `detail_ref_msg_task_variant_overview` (task variants) all resolve live; query them before touching
   an established message's contract.

## Calling a message, parameters, and options

A message is raised from SQL by its `msg_id`; parameters substitute into the translated text, and
`msg_option` rows give the user buttons to choose between.

**The `msg_option` label is shared by the bare `msg_option_id`, not scoped per message** — renaming
one option's text changes it everywhere that id is used.

In a process flow, the **Show message** action raises it and branches on the chosen option.

For the SQL call forms, parameter substitution and translation, the option entities, and the
process-flow wiring, read `references/calling_and_options.md`.

## UX, confirmations, database capture, and runtime behaviour

Writing the message text well, deciding when a task needs a confirmation at all, capturing raw
database errors into modeled messages, and how messages behave outside an interactive session are
each their own sub-task.

For all of it (UX principles for confirmations and multi-option choices, task confirmation messages,
**database message capture** including the capture regex and priority ordering, messages by logic
concept, and API/offline/unattended behaviour), read `references/message_ux_and_capture.md`.

## Naming, text, security, and testing

Reuse an existing message before adding a near-duplicate — message ids are global, and the
`msg_option` label is shared by the bare `msg_option_id`, not scoped per message.

Write the text as a sentence the user can act on: what happened, why, and what to do next. Never put
credentials, connection strings, or raw database errors in a user-facing message.

For the naming conventions, the effective-message-text guidance, security/privacy rules, unit-testing
notes, and the common failure patterns, read `references/message_conventions.md`. For worked examples across the common message families,
read `references/practical_examples.md`.

## Pre-flight checklist

- `msg` added under `branch` (`msg_option` under `msg` if a bare add is refused); `audio_file` read-only; no creation-order
  gate.
- `msg.msg_location_id` holds the literal strings `popup`/`panel`/`suppress`/`debug` — don't look for a
  numeric code there; `severity` *is* a numeric byte enum (`error`=0/`warning`=1/`information`=2).
- Don't confuse `msg.severity` with the SQL Server *database* severity levels (9/16) that
  `tsf_send_message`'s abort flag triggers — same word, unrelated concepts.
- Call `tsf_send_message`/`tsf_send_progress` with their real parameter names
  (`msg_id`/`parmtr_string`/`abort_ind` and `msg_id`/`parmtr_string`/`percentage`), named, like any other
  subroutine call.
- Build parameter XML with `for xml path('text')` or an equivalent safe builder — never hand-built
  string concatenation.
- Aborting a message does not roll back a SQL Server transaction by itself — write the explicit
  `rollback; return;` (or platform equivalent) yourself, and confirm the actual behavior on non-SQL
  Server platforms rather than assuming it matches.
- Message options: `response_type` true=affirmative/false=negative; the Software Factory derives the
  read-only status code from it (ascending from `0` / descending from `-1`) — never send
  `msg_option_status_code`, add options in the order the codes should follow, and read them back.
- Send `msg_regular_expression` before `priority` — `priority` stays read-only until the regex is set.
- **Before naming a new `msg_option_id`, check whether reusing `yes`/`no` is actually fine** — its
  translation is shared by every message using that same bare option id. Give a message-specific label
  its own distinct, subject-prefixed option id (`release_order_anyway`) instead of editing the shared
  `yes`/`no` text.

