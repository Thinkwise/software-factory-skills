# Conditional layout — overlapping layouts, accessibility, and when not to use it

Loaded on demand from `thinkwise_sf_conditional_layouts`.

## Overlapping layouts

Remember: no `order_no`/priority field exists here — see above. Make conditions mutually exclusive
rather than relying on evaluation order:

```text
Problematic — one record can match all three, outcome unpredictable:
  Layout A: due_date < today
  Layout B: status != completed
  Layout C: priority = urgent

Better — mutually exclusive:
  critical_overdue:  due_date < today AND status != completed AND priority = urgent
  normal_overdue:    due_date < today AND status != completed AND priority != urgent
```

Or build one expression field representing the presentation state (`attention_level` =
`CRITICAL`/`WARNING`/`NORMAL`) and define one mutually-exclusive layout per value.

## Accessibility and usability

Never communicate meaning by colour alone — reinforce with at least one of: status text, an icon or
domain element, a badge, a warning message, help text, a dedicated boolean/attention column, or a font
treatment in addition to background colour. Reserve red for actual problems, avoid red/green as the only
distinction, keep text contrast high in both themes, avoid colouring most rows on a screen, and confirm
selected/focused rows stay legible. Conditional-layout help text can be surfaced in the generated
subject help — useful for explaining a colour legend to end users.

## When not to use conditional layout

- The user must be prevented from doing something → validation/rights, not formatting.
- Records should be removed from the screen entirely → a prefilter.
- A field should become hidden/mandatory/read-only → layout logic.
- A task must be unavailable → context procedure/rights.
- A warning must be acknowledged, or the rule must also hold through the API → real validation.
- Nearly every record would be highlighted, or the screen is already visually dense → reconsider scope.
- Universal UI does not support it on radio-button, signature, checkbox, or HTML controls.
