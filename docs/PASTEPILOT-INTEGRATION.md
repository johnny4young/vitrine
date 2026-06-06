# PastePilot integration — design record (CS-081, ⏸ Future)

> **Status: parked.** Design that must exist *before* CS-081 is un-parked, per the roadmap's
> "acceptance before un-parking." A decision record, **not** an implementation. No PastePilot
> coupling exists in this repository today.

## Idea

PastePilot is a separate clipboard-history app (by the same author). The integration lets a
user pick an item from PastePilot's history and **render it with Vitrine** — "this old
snippet → a beautiful image" — without re-copying it by hand.

## Why this is parked

It couples two apps. That is only worth doing once **both are stable** and the integration
can be **user-intent-driven and privacy-safe**. Until then, the value (a minor convenience)
does not justify the coupling and the clipboard-privacy risk.

Un-park only when **all** hold:

1. Both Vitrine and PastePilot are stable, shipping apps.
2. The integration is triggered by an explicit user action — never a background sync.
3. **No silent clipboard-history sharing.** Vitrine receives only the single item the user
   chose, at the moment they choose it.
4. The App Group / URL-scheme security model below is documented and reviewed.

## Direction of the integration

PastePilot is the *source*; Vitrine is the *renderer*. The action originates in PastePilot
("Render with Vitrine" on a history item) and hands **one item** to Vitrine.

```
PastePilot history item ──(explicit "Render with Vitrine")──▶ Vitrine renders it
        (one item, user-initiated)                              (existing local pipeline)
```

## Transport options (security trade-offs)

| Mechanism | Pros | Cons / requirements |
| --- | --- | --- |
| **Custom URL scheme** (`vitrine://render?…`) | Simple, no shared container, OS-mediated | Payload must be small / a handle, not raw code in the URL; validate + size-cap input; never auto-execute; show the editor for confirmation, don't silently export. |
| **App Group** (shared container) | Can pass larger payloads | Both apps must share an App Group entitlement (same team); a shared container is a standing data channel → must be **write-one-item-on-intent, read-once, then clear**; never a continuous mirror of history. |

**Leaning:** URL scheme for the trigger + a one-shot handle into a temporary, per-invocation
App Group file that Vitrine reads exactly once and deletes. The user always lands in the
**editor** (not a silent capture), so the hand-off is visible and cancellable.

## Privacy invariants (hard requirements)

- Vitrine never reads PastePilot's clipboard history. It receives only the one chosen item.
- The shared channel carries a single payload per explicit invocation and is cleared after
  read; it is never a persistent sync.
- The handoff is user-visible (opens the editor) — no background, no auto-export.
- Vitrine's existing local promise is unchanged: the rendered item stays on the Mac.

## What "starting" this ticket means here

This document. No PastePilot coupling, no App Group entitlement, no URL-scheme handler added
to the shipping app yet. When both apps are stable and the model above is approved, CS-081
graduates to implementation.
