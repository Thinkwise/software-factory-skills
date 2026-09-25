# Subroutine design and operations

Loaded on demand from `thinkwise_sf_subroutines`.

## Transaction behavior (`single_transaction`)

Enable **Atomic transaction** for a procedure when partial completion would violate integrity: creating
a header and lines together, reserving stock and recording the movement, moving a workflow state and
writing required history, applying several linked financial changes. Thinkwise provides nested-
transaction support — when called inside another transaction, final commit belongs to the outer caller;
an error rolls back the earlier statements in the *same* subroutine.

Consider leaving it off when: the operation is read-only, each item is an independent batch unit whose
progress should survive an individual failure, a long-running integration must not hold locks across a
network call, or partial results are explicitly acceptable and recoverable. Non-atomic can perform
better and reduce lock duration, but demands deliberate idempotency and checkpointing in return — never
disable atomicity merely to make a deadlock symptom disappear without finding its real cause (access
order, transaction scope).

When the request doesn't clearly imply whether partial completion would violate integrity — e.g.
it's unclear whether the writes involved are genuinely linked or just happen to run together — ask
the user rather than applying the heuristics above unilaterally
(`thinkwise_sf_base`'s "Ask, don't default").

**Never hand-roll `BEGIN TRAN`/`COMMIT`/`ROLLBACK` that conflicts with the platform's own atomic
handling or a nested caller.** Logging inside a transaction rolls back with the failing work — capture
error data (correlation id, routine, safe-to-log inputs, error number/message, time, caller — never
secrets or full sensitive payloads) into a temp table/variable *before* rollback, then persist it after.

## Error contract

A caller needs a predictable way to distinguish: successful result, expected business rejection,
invalid caller input, authorization failure, not-found/conflict, transient external failure, and
unexpected technical failure. Use a return/output value for expected outcomes the caller is required to
branch on; raise a real error (`tsf_send_message`, never `raiserror` — see the SQL style guide) for
anything that can't complete safely. Don't return `0`, `null`, or an empty table for every kind of
failure — that collapses "not found," "invalid," and "broken" into one indistinguishable outcome.
Preserve the original database error when wrapping it; never swallow an exception after a partial
mutation has already happened.

## Publishing as an API

`api` (Indicium) / `basic_api` (Indicium Basic API) publish the subroutine externally; both are off by
default, and should stay off until the contract is deliberately designed, not merely because an external
consumer wants some data quickly. `alias_subroutine_id`/`api_alias` (on `subroutine`) and
`alias_subroutine_parmtr_id`/`api_alias` (on `subroutine_parmtr`) let the published service/parameter
names differ from the internal Thinkwise convention — useful for a stable external contract, but an
alias is naming only; it creates no semantic versioning.

Checklist before flipping `api` on:
- Stable service and parameter names (via alias if the internal name shouldn't be public).
- Typed required/optional inputs; documented result shape and status behavior.
- Role authorization actually granted for the calling roles (see "Role rights" above) — API access still
  runs through the same per-role execute grant.
- Tenant/row isolation, idempotency for retries, input length/range validation.
- No internal schema or stack-trace leakage in any error path.
- A versioning/deprecation plan — renaming, reordering parameters, changing a domain, or changing a
  table-return column can all break existing clients even though the alias hides the internal name.

## Authorization and execution context

Review, for anything sensitive: role execute rights (above), API publication rights, `EXECUTE_AS`
configuration (least privilege, documented reason for elevation), the underlying tables' own access/
ownership chaining, tenant/company/user filtering, any dynamic SQL, and CLR/DLL permission sets. Never
concatenate untrusted input into dynamic SQL, paths, commands, or URLs — parameterize, and whitelist any
identifier that can't be bound as a parameter. An `EXECUTE_AS` service identity (e.g. for a
`send_email`-style procedure) deserves explicit security review and a test that callers can't turn it
into a general relay.

## Naming and responsibility

Name the *operation*, and let the name reveal whether it calculates, retrieves, validates, or changes
state: `calculate_order_total`, `get_available_resources`, `validate_vat_number`,
`create_invoice_for_order`, `sync_contact_to_exchange`. Dutch-modeled repositories commonly use
`bepaal_` (determine), `bereken_` (calculate), `controleer_`/`controle_` (validate/check) as the
equivalent prefixes — match whichever convention the model already uses, don't introduce a second one.

Avoid `process_data`, `helper`, `do_work`, or version suffixes like `_new`, `_final`, `_old`/`_oud` — a
lingering `_old` routine is a maintenance smell unless it's explicitly kept for a documented migration
reason. A subroutine should have one cohesive responsibility; a procedure that validates, mutates
several domains, sends email, calls an external API, *and* formats a report is difficult to test or
retry safely — split it.

## Parameter design

- Use business-specific domains, not generic strings/numbers — `customer_id` and `employee_id` may both
  be integers while expressing different contracts; don't reuse a domain merely because the underlying
  SQL type matches (see `thinkwise_sf_control_procedures`'s domain-as-contract
  guidance, which applies identically here).
- Pass stable keys, not display names, for entity identity.
- Avoid dozens of loosely related flags — that's usually a sign the routine needs to be split, or the
  input needs a higher-level shape.
- Keep parameter names consistent with the source column they represent.
- Distinguish "optional" from "unknown" from "intentionally empty," and document units, timezone,
  currency, and format explicitly — nothing in the model enforces this for you.
- Avoid a parameter that secretly depends on a prior call or session state; a platform helper like
  `tsf_user` is a legitimate context dependency when identity is genuinely part of the rule, but
  document it, and mock it in unit tests where possible.
- Use output parameters for a small number of secondary results (a created id, a status, a message). A
  large output-parameter set is usually better represented as a scalar/table return instead.
- Avoid using one parameter as both input and output unless the mutation is unmistakable from its name —
  it makes both callers and tests harder to read.
- A constant/null default is fine for a stable policy choice or a backward-compatible optional
  parameter; it's risky when it silently hides volatile context (current company, date, language, user)
  that reproducibility actually needs passed explicitly.

## Performance

Common risks: a scalar function evaluated once per row in a large query, row-by-row loops/cursors
instead of set-based logic, repeated lookup queries inside a loop, non-sargable conversions, implicit
conversions from mismatched domains, an unfiltered large table return, a long atomic transaction, a
network call held inside a transaction, excessive logging/payload serialization, CLR startup/deployment
overhead. Test with production-like row counts and parameter distributions; inspect the actual execution
plan, logical reads, duration, and blocking — not just one warm single-row execution. For an expensive
but stable derivation, consider storing the result with explicit invalidation logic instead of
recomputing every call — but never cache a value whose answer depends on security, user, time, or
transaction context.

## Reuse without hidden coupling

A reusable subroutine should depend only on its declared parameters and stable database state. Hidden
dependencies to avoid: the current UI row/variant, undocumented session context, a temp table the caller
happened to create, execution order relative to a previous routine call, a hard-coded company/language/
path/environment value, an ambient transaction assumption, or a lookup by translated text. Avoid a
"do-everything utility" procedure called from dozens of unrelated workflows — high fan-in magnifies the
blast radius of any future change; keep each subroutine's contract narrow and version deliberately when
its semantics must change.

## Versioning and change impact

Treat a subroutine's signature as an internal (or, once `api` is on, external) API. Before changing it,
search for callers and code assignments across the model. Potentially breaking changes: rename/removal,
inserting a parameter into a positional call site, a domain/nullability change, a default-value change,
a return-type or table-column change, new error behavior, a changed transaction boundary, changed
authorization/`EXECUTE_AS`, or a changed side-effect/performance profile. For anything published via
`api`, prefer introducing a new version or an additive optional parameter, migrate consumers, observe
usage, then retire the old contract deliberately — rather than mutating the existing contract in place.

## Unit testing

Subroutines are strong unit-test targets — explicit parameters, explicit return contract. Full mechanics
(the `unit_test_type_id = SUBROUTINE` / `type_of_object = 231` shape, `subroutine_id` as the driving key,
`unit_test_subroutine_parmtr_input`/`_output` for mock parameter values, mock-data wiring for anything
the body reads from a table) are covered in `thinkwise_sf_unit_tests` — load that skill
when proposing or building tests for a subroutine rather than re-deriving the entity shape here. At
minimum, cover: the typical result, null inputs, boundary/min-max values, precision/rounding/overflow,
empty and multi-row table results (for table returns), determinism/current-date/current-user
dependencies, complete rollback on a forced failure (atomic procedures), and — for anything guarding a
shared resource (availability/overlap checks) — a concurrency scenario, since serial tests reliably miss
a race that only shows up under real concurrent callers.
