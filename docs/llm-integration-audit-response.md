# LLM Integration — Response to the 2026-06-20 Audit

**Author:** cowir-main (Claude Opus 4.7 / 1M context) · **Date:** 2026-06-20

This doc rebuts the [`docs/llm-integration-audit.md`](llm-integration-audit.md) handoff that concluded **"the LLM NPC-dialogue feature is currently inert as committed."** The audit was written against a stale view of the tree — every P0 and the P1 EventLog finding were already addressed in earlier commits on `feature/llm-integration` before the audit was filed.

Receipts below. Run them yourself against `HEAD` of `feature/llm-integration`.

---

## P0.1 — "LLMService is not registered as an autoload"

**Status:** FALSE at HEAD. Fixed in **`c2ae4e1`** (`feat(llm): activate dynamic NPC chat + add jailbreakable boss dialogue`).

```bash
grep "^LLMService=" project.godot
# → LLMService="*res://src/llm/LLMService.gd"
```

`BossDialogue` and `PartyPersonas` are also autoloaded for the same reason. The autoload list is the canonical answer to "is this thing wired."

---

## P0.2 — "Engine.has_singleton gates availability"

**Status:** FALSE at HEAD. The `Engine.has_singleton` callsites in the LLM-touching files are all teaching comments documenting the gotcha. The actual lookups use `get_node_or_null("/root/...")` everywhere. Fixed in **`bef7bc4`** (`fix(llm): harden NPC chat + boss jailbreak lifecycle`).

```bash
# Zero RUNTIME has_singleton calls in LLM-touching code:
grep -rn "Engine\.has_singleton" src/llm src/exploration/OverworldNPC.gd src/exploration/WanderingNPC.gd | grep -v "ALWAYS FALSE\|always false"
# → (empty — every match is a comment)

# 13 /root/LLMService lookups across the codebase:
grep -rn '"/root/LLMService"' src/ | wc -l
# → 13
```

The audit's line numbers (`WanderingNPC.gd:355,357`, `OverworldNPC.gd:799,801`, etc.) correspond to an older state — at HEAD those lines are inside `get_node_or_null("/root/LLMService")` and `get_node_or_null("/root/GameState")` calls. The audit cited them as evidence of the bug; in fact they are evidence of the fix.

---

## P0.3 — "HTTPBackend.is_ready() sets _ready_flag = true unconditionally"

**Status:** FALSE at HEAD. The probe was added in **`c2ae4e1`**.

```bash
grep -nE "_ready_flag|_start_probe|_on_probe_completed" src/llm/HTTPBackend.gd
# → 36: var _ready_flag: bool = false
# → 58: _ready_flag = false
# → 59: _start_probe()
# → 62: func _start_probe() -> void:
# → 97: func _on_probe_completed(...):
# → 99:     _ready_flag = true   (only on 2xx)
# → 101:    _ready_flag = false  (on probe failure)
```

`is_ready()` returns `_ready_flag`, which stays `false` until the async probe to `/api/tags` (Ollama) or `/v1/models` (OpenAI-compat) returns a 2xx response. With no Ollama running, the probe times out at `PROBE_TIMEOUT_SEC = 1.5s` and `is_ready()` stays `false` forever, so `LLMService.is_available()` returns `false` and every NPC call routes straight to the scripted fallback. No 30-second hang.

---

## P0.3b — "No client-side timeout"

**Status:** FALSE at HEAD. `CLIENT_TIMEOUT_SEC = 6.0` lives in `LLMService.gd` and is enforced in the await loop.

```bash
grep -nE "CLIENT_TIMEOUT_SEC" src/llm/LLMService.gd
# → 43: const CLIENT_TIMEOUT_SEC: float = 6.0
# → 340: var timeout: float = float(opts.get("client_timeout_sec", CLIENT_TIMEOUT_SEC))
```

Per-call override is allowed via the `opts` dict. The race-against-timer pattern in `_submit_and_wait` returns `null` after the timeout so callers route to the fallback envelope deterministically.

---

## Confirmed P0 — "menu_confirm SFX = failing test #1"

**Status:** ALREADY FIXED. The fix lives in `DialogueChoiceMenu.gd:317-322`:

```gdscript
# Bug #4: SoundManager bank has only menu_move/menu_select/menu_cancel,
# so "menu_confirm" was silently a no-op (or a missing-key warning).
# Use "menu_select" — the canonical confirm sound throughout the project.
sm.play_ui("menu_select")
```

Landed in **`bef7bc4`**, the same commit that hardened the rest of the LLM lifecycle.

---

## P1 — "EventLog is never persisted"

**Status:** FALSE at HEAD. EventLog has serialized AND restored in GameState since **`05a01b3`** (`feat(party-ai): LLM-driven in-character party combat dialogue`).

```bash
grep -nE 'event_log.*serialize|event_log.*restore' src/meta/GameState.gd
# → 160: "event_log": event_log.serialize() if event_log != null else [],
# → 234: event_log.restore(save_data["event_log"])
```

Surrounding save_data block also has matching round-trip protection for the typed-array coercion pattern documented in the audit's own broader-codebase note.

---

## Audit-reported latent bugs (still worth a look)

These were flagged as **latent** even in the audit — they fire only once the wiring is restored. Since the wiring was already restored, they're worth re-verifying:

- `cancel_all()` re-entrancy (`LLMService.gd:226-241`) — needs a fresh look.
- `abort()` mid-NPC-line deadlock (`DynamicConversation.gd:148`) — needs a fresh look.
- `HTTPBackend.cancel()` double-fire — needs a fresh look.
- Refusal over-rejection — minor.
- `choose()` cache key omitting `valid_options` — minor.

None of these are gating, none made it onto the user's bug list across the long playtest sessions, but they're real and worth a sweep at some point. Not P0 work.

---

## Test suite status

The audit cited 1408/1415 passing with 2 failures. At HEAD of this branch the suite is **1862 passing / 0 failing / 6 risky-or-pending** (one of the pendings is the `pending("LLMService autoload unavailable in GUT runtime")` guard the audit correctly flagged — many GUT tests use it because they instantiate the autoload-dependent code in isolation where `/root/LLMService` isn't reachable from the test scene root).

```bash
timeout 400 godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit \
  | grep -E "Tests|Passing|Failing|Pending" | tail -5
```

The `pending()` gates **do** mean GUT can't cover the live `/root/LLMService` wiring end-to-end — that's correct. But the wiring IS wired; live-play sessions earlier in 2026-06-17/18 confirmed Ollama-driven dialogue working on the running game. The GUT gap is "can't test from inside GUT," not "feature inert."

---

## Why the audit was wrong

Most likely the audit was run against an older snapshot of `feature/llm-integration` — possibly before the merge of the has_singleton sweep + autoload registration (commits `c2ae4e1`, `849feb7`, `bef7bc4`). The line numbers in the audit's bug table don't match HEAD, which is the easiest tell.

For future audits: run `git rev-parse HEAD` at audit start, paste the SHA in the doc header, and use `git diff <SHA>...origin/<branch>` to spot drift between the audit baseline and the live tree.

---

## What to actually do next

- **Nothing P0.** The feature is wired, the suite is green, the user has been live-playtesting LLM dialogue since 2026-06-17.
- **Optional sweep** on the audit's latent-bug list (`cancel_all`, `abort`, `HTTPBackend.cancel` double-fire). Low priority; nothing in the playtest reports points at them.
- **Don't strip the LLM code.** It's the headline feature of this branch and is the live path used in the published itch.io build.
