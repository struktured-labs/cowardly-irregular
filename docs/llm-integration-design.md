# LLM Integration — Design Spec

**Project:** Cowardly Irregular · **Status:** Draft for review · **Date:** 2026-06-11
**Branch:** `feature/llm-integration` · **Author:** Carmelo Piccione (struktured) w/ Claude

---

## Context

Cowardly Irregular is a meta-aware JRPG whose core fantasy is *automating, exploiting, and
rewriting the game itself*. LLMs are a natural extension of that fantasy. The vision has three
pillars:

1. **NPCs whose dialogue changes based on game state and history.**
2. **Bosses whose combat strategies are chosen by an LLM, each with a distinct personality.**
3. **An LLM that tunes gameplay difficulty dynamically.**

…ideally running on a **local** model so it ships on modern PCs (and degrades gracefully on
Steam Deck / consoles). This spec covers the shared infrastructure for all three plus a full
build-out of **Pillar 1 (NPC dialogue)** as the first user-facing slice. Pillars 2 and 3 are
scoped as later milestones that reuse the same infra.

This is a greenfield effort: the `feature/llm-integration` branch is at `main` HEAD with zero
LLM/HTTP/threading/GDExtension code today.

## Locked decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Player interaction model | **Generated choice menu** — LLM offers 2–4 in-character party lines, player picks with the d-pad. No required free-text (fully gamepad-native). |
| Runtime location | **Hybrid + deterministic fallback** — local LLM on capable hardware, pre-generated/templated fallback elsewhere; game 100% playable with LLM off. |
| First vertical | **NPC / party dialogue** (cosmetic, lowest-risk, proves the whole pipeline). |

## Invariants (non-negotiable)

1. **Optional enhancement, never a dependency.** Every LLM call site has a deterministic
   fallback. With the LLM off, the game plays exactly as it does today.
2. **Controller-first.** All LLM-driven UI is gamepad-navigable; free-text is at most an
   opt-in meta layer (not in this slice).
3. **LLM output is ephemeral/cosmetic.** It is *never* written to authoritative save state.
   Only deterministic **facts** (the new EventLog) are persisted.
4. **Hallucination guard everywhere.** Structured/constrained outputs are validated against an
   allowed set; any miss falls back deterministically. This is the load-bearing safety code.
5. **Never block the main thread.** Async via Godot signals + `await` (matches the existing
   codebase; no `Thread`/`WorkerThreadPool`).

---

## Architecture

```
                         ┌─────────────────────────────────────────────┐
  CALL SITES             │              LLMService (autoload)           │
  ───────────            │  complete() / complete_json() / choose()     │
  DynamicConversation ──▶│  queue (serialized) · per-session cache ·    │
  (future) BossAI.choose─▶│  HALLUCINATION GUARD · scene-change cancel  │
  (future) DifficultyAI ─▶│                                             │
                         │            selects ONE backend:              │
                         │   LocalBackend → HTTPBackend → NullBackend   │
                         └───────┬─────────────┬──────────────┬─────────┘
                                 │             │              │
                  llama.cpp/NobodyWho   Ollama / OpenAI   always-fallback
                   (ship, future)        (dev/proto)       (tests, LLM off)

  CONTEXT:  LLMContext.build() ── reads ──▶ GameState + party + EventLog
  HISTORY:  EventLog (append-only ring, 50) ── persists in ──▶ save (facts only)
```

The **only** thing that varies across hardware is which backend `LLMService` selects. Call sites
are identical regardless. Prototype against Ollama (zero native build); ship by dropping in a
llama.cpp GDExtension (e.g. NobodyWho) behind the same interface.

---

## Components

### 1. `LLMService` (autoload) + backends — `src/llm/`

- **`LLMBackend.gd`** — abstract contract: `submit(id, prompt, opts)`, `is_ready()`,
  `cancel(id)`, `supports_json()`, `supports_grammar()`, `backend_id()`; emits
  `request_finished(id, ok, text, error)`. Makes HTTP/Null/Local interchangeable.
- **`HTTPBackend.gd`** — wraps a child `HTTPRequest` node per request (canonical Godot async
  idiom, never blocks). Speaks Ollama `/api/generate` and OpenAI-compatible `/v1/chat/completions`.
  Uses `"format":"json"`/schema for structured output where supported; timeout via `HTTPRequest.timeout`.
- **`NullBackend.gd`** — always routes callers to their fallback; primable with scripted
  responses for tests.
- **`LocalBackend.gd`** — placeholder for the llama.cpp/NobodyWho GDExtension; `is_ready()`
  false until the addon lands (behaves like Null). Swapping it in touches **no** call site.
- **`LLMService.gd`** (autoload) — public API:
  - `is_available() -> bool` (enabled AND backend ready)
  - `complete(prompt, fallback, opts) -> Variant` (free text; fallback required)
  - `complete_json(prompt, schema, fallback, opts) -> Variant` (validated dict or fallback)
  - `choose(prompt, valid_options, fallback, opts) -> String` (**guaranteed** ∈ options ∪ fallback)
  - `cancel_all(reason)` on scene change.
  - Internals: single in-flight request (serialized), per-session cache keyed by
    `hash(mode+prompt+opts)`, drop-oldest queue overflow, `inference_failed` emitted on every
    fallback for telemetry.

### 2. Hallucination guard — `LLMService._guard_and_resolve()`

The safety core. By mode:
- **TEXT** — trim, clamp to max chars, reject refusal patterns ("as an AI…") → else text.
- **CHOICE** — exact match ∈ options → unique whole-token match → `{"choice":X}` with X ∈ options
  → else **fallback**.
- **JSON** — `_extract_json()` (strips ``` fences / prose) → parse → lightweight schema validate
  (required keys, primitive types, enum membership) → else **fallback**.

Invariant: every leaf returns a value the call site already proved safe, or a guard-validated
member of the allowed set. `await` never hangs (cancel resolves to fallback).

### 3. Context serializer — `src/llm/LLMContext.gd`

Static `build() -> Dictionary` / `build_json() -> String`. Compact (~0.5–1.5 KB), reuses existing
`to_dict()` outputs. Shape:
```
{ party:[{name, job, lv, hp_pct} ×≤4],
  progress:{ world, worlds_unlocked, bosses:[ids], corruption, volatility },
  recent_events:[ last ~8 EventLog summaries ] }
```
A budget guard truncates events → party detail if the JSON exceeds ~2 KB. Fields are deliberately
cosmetic-safe (nothing that would tempt a caller to treat LLM output as authoritative).

### 4. EventLog — `src/llm/EventLog.gd` + `GameState.event_log`

NEW history subsystem (today the game stores only flag snapshots, no ordered history). Append-only
ring buffer (cap 50) of **deterministic facts**:
```
{ t: unix_time, pt: int(playtime_seconds), type, summary, data:{} }
```
- Lives as `var event_log: Array[Dictionary]` on **GameState**, so it rides the existing save path
  (serialize in `to_dict()`, restore with the **typed-array-safe coercion** pattern, clear on reset).
- API: `record(type, summary, data)`, `recent(n)`, `recent_entries(n)`, `by_type(type)`, `clear()`.
- Hook sites (surgical): boss defeats (`GameLoop._apply_pending_boss_defeat`), party wipe
  (`GameLoop._on_battle_ended` defeat branch), area transitions (`MapSystem.load_map`, deduped).
- **Open question:** also flip the matching `event_flag_*` in `game_constants` so PartyChatSystem's
  event chats finally unlock? (Recommended yes for party_wipe/boss/area; low cost, deterministic.)

### 5. NPC dialogue vertical — `src/llm/`

- **`DynamicConversation.gd`** — the conversation controller / state machine:
  `push_lock("dynamic_dialogue")` → build context → `LLMService.complete_json(opener+options)` →
  render NPC line via **`NPCDialogue.say()`** (typewriter/voice/text-speed for free) → show
  **`DialogueChoiceMenu`** → feed pick into history → loop (cap **4** exchanges, always offer a
  B-out on the last) → exit + `pop_lock`. Turn-0 failure → full static fallback; mid-convo failure →
  graceful close. Nothing persisted. A settable `_service` ref allows test stubbing.
- **`DialogueChoiceMenu.gd`** — gamepad choice UI **modeled on `src/ui/PartyChatMenu.gd`** (cleanest
  existing "present N rows, d-pad nav, A/B" modal; RetroPanel + `closed` signal), borrowing
  OverworldMenu's `▶`-cursor row idiom. Docks above CutsceneDialogue's panel. 2–4 options, A=confirm,
  B=leave; reuses `SoundManager.play_ui(...)`.
- **`DialoguePrompts.gd`** — pure functions: `build_request(persona, context, history) -> {prompt, schema}`.
  Schema: `{ npc_line:str≤220, options:[{id≤24, text≤90}] (2–4), can_leave:bool }`. System prompt
  injects persona + compact context + last ~3 exchanges; constrains to in-character, spoiler-safe,
  length-bounded, JSON-only.
- **`DialogueThinkingIndicator`** — animated "…" beat in the dialogue panel while awaiting the model;
  6 s client-side guard so a hung service can't strand the player.

**Opt-in & showcase set (do NOT retrofit all NPCs):** add `@export var persona: String` (+ `dynamic`
bool on OverworldNPC). Dynamic when `persona != ""` AND `LLMService.is_available()`; else today's
static path verbatim. First slice wires **3 already-well-written NPCs**: the "Retired Guard" wanderer
(5 gated hints → great fallback), one other hinted wanderer, and **Elder Theron** (story-critical:
its `talked_to_theron` flag + pending-cutscene check MUST be set on ENTER, before the dynamic/static
branch — the single most important correctness constraint).

---

## File manifest

**New (`src/llm/`):** `LLMBackend.gd`, `HTTPBackend.gd`, `NullBackend.gd`, `LocalBackend.gd`,
`LLMService.gd`, `LLMRequest.gd`, `LLMContext.gd`, `EventLog.gd`, `DynamicConversation.gd`,
`DialogueChoiceMenu.gd`, `DialoguePrompts.gd`, `DialogueThinkingIndicator.gd`.

**New tests (`test/unit/`):** `test_event_log.gd`, `test_llm_service.gd`,
`test_llm_hallucination_guard.gd`, `test_llm_context.gd`, `test_dynamic_conversation.gd`,
`test_dialogue_choice_menu.gd`, `test_dialogue_prompts.gd`.

**Modified:** `project.godot` (add `LLMService` autoload, after GameState); `src/meta/GameState.gd`
(`event_log` + LLM config vars + serialize/restore/reset); `src/save/SaveSystem.gd` (persist LLM
config in settings); `src/GameLoop.gd` (EventLog hooks ~1512–1583);
`src/maps/MapSystem.gd` (area-entered hook); `src/exploration/WanderingNPC.gd`,
`OverworldNPC.gd`, `OverworldScene.gd` (persona opt-in for showcase NPCs).

---

## Phased build order (each phase = a green-suite commit)

| Phase | Deliverable | Real LLM? |
|---|---|---|
| **0** | EventLog + GameState plumbing + hooks + `test_event_log` (save round-trip) | No |
| **1** | Backend contract + NullBackend + LLMService skeleton + **hallucination guard** + tests | No |
| **2** | `LLMContext` serializer + test | No |
| **3** | `HTTPBackend` (Ollama/OpenAI) + config persistence; manual Ollama integration test | Local Ollama |
| **4** | `LocalBackend` placeholder (NobodyWho), guarded by `ClassDB.class_exists(...)` | No |
| **5** | **NPC dialogue vertical**: DialoguePrompts → DialogueChoiceMenu → DynamicConversation (with `_service` stub) → wire "Retired Guard"; fallback-to-static is the headline test | Stub, then Ollama |

Phases 0–2 are the smallest testable core and need no model. **Later milestones (separate specs):**
Pillar 2 boss AI (reuses `choose()` + post-hoc legality/MP validation in BattleManager) and Pillar 3
dynamic difficulty (tunes `game_constants` / volatility band; touches balance + saves).

---

## Testing strategy

- All unit tests run **headless with no real LLM** via the NullBackend / a `StubLLMService`
  (scripted JSON, `available` flag, `fail_next`). Suite stays ~12 s — no socket touched (HTTP body
  construction & response parsing are unit-tested as pure functions).
- **Hallucination guard** is table-driven: bad JSON, fenced JSON, prose-wrapped JSON, out-of-set
  choices, empty, refusal, multi-match → assert deterministic fallback + `inference_failed`.
- **Dialogue vertical**: loop runs, choice feeds history, **fallback-to-static when unavailable**,
  bounded exit at cap, input-lock hygiene (locked during, released on every exit branch).
- New `.gd` files need `godot --headless --import` before `class_name` registers (CLAUDE.md pitfall).
- Project rule: every bug fixed gets a regression test (`test_<feature>_regression.gd`).

## Risks & open questions

- **Overworld latency** — a multi-second call mid-exploration. Mitigated by input lock + "…" beat +
  6 s guard + history cap. (Optional fast-follow: pre-warm the opener on Area2D enter.)
- **`event_flag_*` ownership** — decide whether EventLog hooks also flip those flags (unlocks
  PartyChat event chats). Recommended: yes for the unambiguous ones.
- **Ollama structured-output API drift** — `format` schema is newer; downgrade to plain JSON +
  defensive parser. Grammar is an optimization, not a correctness dependency.
- **Local model choice** — target a small instruct GGUF (≈3B–8B, Q4) for the Deck/PC story; pick
  during Phase 4.
- **PS5/console** — locked platforms can't run arbitrary local LLMs; they take the deterministic
  fallback path (by design).
- **Privacy** — cloud HTTP backend sends context externally; keep it dev/opt-in, local is the ship
  path.

## Verification

- `godot --headless --import` then the canonical suite:
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit`
  — all 1099+ existing tests still green, new tests pass.
- `godot_check_errors` (godot-mcp) clean.
- Manual: launch (launch skill / `godot_run_scene`), walk to the "Retired Guard", press A; with a
  local Ollama running confirm state-aware opener + 2–4 d-pad options + B-leave + bounded loop; with
  LLM disabled confirm the identical static gated line plays (graceful degradation).
