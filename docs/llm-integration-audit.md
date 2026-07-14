# LLM Integration — Audit & Handoff Notes

**Date:** 2026-06-20 · **Branch:** `feature/llm-integration` · **Status:** Audit complete — **fixes NOT applied** (stood down at user's request). This is a handoff for the next agent.

Companion to the design spec: [`docs/llm-integration-design.md`](llm-integration-design.md).

---

## TL;DR

1. **The LLM NPC-dialogue feature is currently inert as committed** — every NPC silently falls back to static dialogue. It *worked recently* (confirmed by the author, talking to a first-village NPC backed by **Ollama**), so this is a **regression**: the commit that landed the feature dropped its wiring.
2. **Two root causes** make it dead code right now:
   - `LLMService` is **not registered as an autoload** in `project.godot`.
   - Even if it were, the new code gates availability on `Engine.has_singleton("LLMService")`, which returns **`false` for Godot autoloads** in this build (4.3). **Empirically verified** with a probe: `Engine.has_singleton("GameState")` and `("SoundManager")` are *also* `false`, while `/root/GameState` etc. exist. Autoloads are `/root` nodes, **not** engine singletons.
3. **Still Ollama-default, not cloud.** `HTTPBackend` defaults to `base_url="http://localhost:11434"`, `api_format="ollama"`. OpenAI-compatible cloud is supported but opt-in only (`api_format="openai"` + `api_key`); nothing in the committed code selects it.
4. **Test suite:** 1408/1415 pass. Of the 2 failures, **only one is ours** (`menu_confirm` SFX); the other is pre-existing and unrelated.

---

## P0 — Restore the feature (this is what regressed)

1. **Register the autoload.** Add to `project.godot` `[autoload]` (after `GameState`, ~line 22):
   ```
   LLMService="*res://src/llm/LLMService.gd"
   ```
2. **Fix autoload access.** Replace `Engine.has_singleton(...)` / `Engine.get_singleton(...)` with the codebase's idiomatic bare-global (`LLMService`, `GameState`, `SoundManager`) or `get_node_or_null("/root/X")`. The codebase documents this exact gotcha in `PartyChatSystem.gd:282`. Sites in the **new** code:
   | File | Lines | Autoload |
   |---|---|---|
   | `src/llm/DynamicConversation.gd` | 363, 365, 371, 373 | LLMService |
   | `src/exploration/WanderingNPC.gd` | 355, 357 (LLMService); 370, 371 (GameState) | both |
   | `src/exploration/OverworldNPC.gd` | 799, 801 (LLMService); 817, 818 (GameState) | both |
   | `src/llm/EventLog.gd` | 44, 45 | GameState |
   | `src/llm/LLMContext.gd` | 37, 41 | GameState |
   | `src/llm/DialogueChoiceMenu.gd` | 266–267, 289–290, 299–300, 316–317 | SoundManager (sounds currently never play!) |
3. **Make `is_ready()` honest** (`src/llm/HTTPBackend.gd:41-55`). It sets `_ready_flag = true` unconditionally (no probe). Combined with `LLMService.llm_enabled = true` (default, `LLMService.gd:54`), `is_available()` returns `true` **even when no Ollama server is running** → every NPC line waits the full `default_timeout_sec` (**30 s**, `HTTPBackend.gd:29`) before falling back. There's no client-side timeout in `DynamicConversation` either. **Fix:** async reachability probe so `is_ready()` reflects a reachable endpoint (no Ollama → instant static fallback), or a short client-side `await`-with-timeout (~3–6 s, per the design's never-implemented "thinking-indicator guard"). This also keeps the suite green in CI without Ollama.

> ⚠️ Restoring the feature **activates the latent P2 bugs below.** Fix at least the leaks + the `abort()` deadlock before shipping it enabled to players.

---

## Confirmed bugs (verified directly against source)

| Sev | File:line | Issue | Fix |
|---|---|---|---|
| **P0** | `DialogueChoiceMenu.gd:292` | Plays unauthored SFX key `"menu_confirm"` → red `test_sfx_key_orphan_audit` (this is failing-test #1). Every other key here is authored (`menu_move`, `menu_cancel`). | Change to `"menu_select"` (the authored confirm sound). |
| **P1** | `GameState.gd:86,107` + `EventLog.gd:99,106` | **EventLog is never persisted.** `event_log` is created and recorded into, but `GameState._create_save_data()/_apply_save_data()` never call `EventLog.serialize()/restore()` (zero callers — verified). History silently dies on every save/load — exactly the "silent failure" class the project's integrity rules target. | Add `"event_log": event_log.serialize()` to the save dict; restore via `event_log.restore(save_data.get("event_log"))` (the typed-array-safe `restore()` already exists). **Add a GameState-level round-trip regression test.** |

---

## Audit-reported bugs (traced by review agents; re-verify before fixing)

These were found by the parallel review agents and look correct from their traces, but I did **not** personally reproduce each — confirm first. They are **latent** today (feature is inert) and fire once P0 wiring lands.

- **`cancel_all()` await-hang** (`LLMService.gd:226-241`): with one request in-flight **and** one queued, a synchronous backend cancel re-enters `_process_queue()`, re-dispatches the queued id, then `cancel_all` clobbers `_inflight_id=""` → the re-dispatched request's `await` never resolves. *Note:* `cancel_all` is **not wired to scene changes anywhere** (grep), so it's dormant. Wire it into `SceneTransition`/`GameLoop` teardown **and** fix the re-entrancy together.
- **`abort()` mid-NPC-line deadlock** (`DynamicConversation.gd:148`): if `abort()` runs while `run()` is parked on `await NPCDialogue.say(...)`, that signal never fires → `run()` never reaches its movement-unfreeze line → **player soft-freezes**. `abort()` has no `player` ref to recover. Store `player` in `run()`; force-resolve/dismiss the NPCDialogue in `abort()`.
- **Node leaks** (fire when enabled): per-request `HTTPRequest` children stranded on scene change (`HTTPBackend` + missing `cancel_all` wiring); `NPCDialogue`/`CutsceneDialogue` never freed ("own lifecycle" doesn't exist — `NPCDialogue` has no `_exit_tree`); `DialogueChoiceMenu` dim `ColorRect` re-added per `present()`. These match the `ShapedText`/`DummyTexture` leak signature *if* the path were live (it isn't yet — the 124 orphans in the current run are **pre-existing, non-LLM** tests).
- **`HTTPBackend.cancel()` double-fire** (`HTTPBackend.gd:100-106`): a late `request_completed` after `cancel_request()` can emit `request_finished` twice; use `CONNECT_ONE_SHOT` or guard on `_inflight.has(id)`.
- **Timeout guard checks the wrong value** (`HTTPBackend.gd:76-77`): guards on `default_timeout_sec` not the effective per-request value.
- **Refusal over-rejection** (`LLMService.gd:345-348`): `lower.contains("i cannot" / "i'm an ai")` discards valid in-character lines ("I cannot lower the price"; "I'm an aide"). Low impact for NPC dialogue (which uses `complete_json`/`_guard_json`, not `_guard_text`), but tighten to word boundaries. The **guard's core value-validation is sound** — every invalid `choose()`/`complete_json()` input correctly falls through to fallback.
- **`choose()` cache key omits `valid_options`** (`LLMService.gd:486`): same prompt + different option sets collide; the membership recheck at `:207` prevents a *wrong* return (not a guard hole) but kills the cache for reused prompts.

---

## Test status & gaps

- **Failure #1 (ours):** `test_sfx_key_orphan_audit.gd` → `menu_confirm`. Real, fixed by the P0 SFX change.
- **Failure #2 (NOT ours):** `test_menu_input_regression.gd::test_win98_menu_input_delay_flag` (line 49). **Pre-existing**, deterministic headless-timing bug in `Win98Menu` — `git diff main...HEAD` shows zero changes to those files. **Out of scope** for the LLM PR.
- **Why C1/C2 slipped past 194 green LLM tests:** every LLM-path test gates on `if Engine.has_singleton("LLMService"): pending()` — always false — and exercises components in isolation with stubbed/`preload().new()` services. The **live wiring and the real save path are never tested**, so "dead feature" + "unpersisted EventLog" both read green.
- **Highest-value missing tests** (add with the fixes): public `choose()` returns ∈ options∪fallback on hallucinated input via a **primed** NullBackend; `complete_json()` invalid→fallback end-to-end; `DynamicConversation.run()` actually exits at `MAX_EXCHANGES`; player movement freeze/unfreeze balance incl. the `abort()` branch; `LLMService.cancel_all()` routes pending→fallback. **Make these deterministic by setting `LLMService.llm_enabled = false`** in LLM tests so the suite never depends on whether Ollama is running.

---

## Broader codebase note (not LLM-specific)

The `Engine.has_singleton("<autoload>") == false` fact means the *same idiom* is likely silently degrading elsewhere: `VolatilitySystem.gd:128` (GameState), `SettingsMenu.gd:871` (SaveSystem), `HeadlessBattleResolver.gd:50` (BattleManager), `TreasureChest.gd:404`, `PartyStatusScreen.gd:414`, `SpriteUtils.gd:53`. Worth a separate sweep — each has a fallback branch so failures are silent.

---

## Recommended order for the next agent

1. **P0 wiring** (autoload + access pattern) → restores the Ollama-backed feature the author already used.
2. **P0** `menu_confirm` → `menu_select` (green suite).
3. **P1** EventLog persistence + GameState round-trip regression test.
4. **P1** `is_ready()` reachability / client timeout (no-Ollama degrades instantly; CI stays green).
5. **P2** leaks + `abort()` deadlock + `cancel_all` (+ wire it to scene changes) — before enabling for players.
6. Add the missing safety/e2e tests; make LLM tests `llm_enabled=false`-deterministic.

**Verify:** `godot --headless --import` then
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit`
(expect the 2 known failures to drop to 1 after the SFX fix; #2 is pre-existing). Manual: with `ollama serve` running, talk to the first-village "Retired Guard"; confirm a state-aware opener + d-pad options; then stop Ollama and confirm instant static fallback.

---

*Audit performed by 4 parallel read-only review agents (safety/guard, async/lifecycle, integration/save, test-quality) plus direct source verification of the P0/P1 claims. Findings attributed as "confirmed" (verified here) vs "audit-reported" (agent-traced, re-verify).*
