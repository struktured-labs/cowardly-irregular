# LLM Rule Composer + Monster Adaptation — Design Spec

**Date:** 2026-07-01
**Author:** cowir-ai
**Playtest backlog items:** #20 (LLM-driven helper for autobattle + autogrind rule authoring), #27 (monsters that learn against the player in autobattle)
**Baseline:** `main` @ `f763dc8d` (v3.31.0-alpha track)
**Owning session:** cowir-ai
**Cross-huddle:** cowir-autogrind (rule-editor UI seams), cowir-battle (Boss Strategic Intent extensions)
**Status:** SPEC — awaiting review; no code until greenlit

---

## 1. Goals & non-goals

**Goal A (item 20 — Rule Composer).** Player opens the autobattle grid editor or the autogrind rule editor, invokes an LLM assistant with natural language ("always heal if HP low, use fire on ice, never waste MP"), and receives a draft ruleset rendered in the target grammar with an accept/tweak overlay. The composer bridges the UX gap between curated preset (cowir-autogrind task #6: Safe Grind / EXP Rush / Gold Farm) and hand-authored grid.

**Goal B (item 27 — Learning Monsters).** LLM-enabled bosses read the player's autobattle rule shape (per PC) and the region's rolling battle patterns, and pivot their **strategic intent** — never their action pool — to counter that shape. Extend the existing Boss Strategic Intent seam (deterministic first, LLM refine after) already shipped for the 5 W1 bosses.

**Shared substrate.** BYOK config, `LLMService.complete_json` with schema-validated fallback, and the `BossDialogue.pick_intent_async` deterministic-first / LLM-refine pattern. Both features degrade cleanly when LLM is off (offline, web build, BYOK unconfigured, timeout).

**Non-goals for this spec.**
- Replacing the grid editors. Both features augment; the editor remains authoritative.
- Per-role model routing (translator vs chat). YAGNI — same model for v1; add `opts.model_override` in a follow-up if quality issues surface.
- Extending LLM adaptation to arbitrary monsters. Only bosses with `data/boss_dialogue.json` opt-in (currently 5 W1 bosses) use the LLM refine path. Regular monsters keep the existing deterministic `learned_patterns` behavior unchanged.
- Nested-schema support in `LLMService.complete_json`. The two-pass pattern (LLM emits JSON as a string field, code parses + hard-validates) is battle-tested by `BossDialogue`; extending the schema stack is scope creep.
- Voice input (spec is text-only). Hooks into any future voice-in are additive.

---

## 2. Architecture

Two independent modules, one shared constant.

```
                ┌─ src/llm/RuleComposer.gd (NEW autoload) ─┐
                │  translate NL → rule draft               │
                │  domain: "autobattle" | "autogrind"      │
                └──────────────────┬───────────────────────┘
                                   │
    src/llm/DialoguePrompts.gd ────┤  shared:
       AUTOBATTLE_GRAMMAR_DESC     │  AUTOBATTLE_GRAMMAR_DESCRIPTION const
       AUTOGRIND_GRAMMAR_DESC      │  AUTOGRIND_GRAMMAR_DESCRIPTION  const
       SCHEMA_RULE_COMPOSITION     │  SCHEMA_RULE_COMPOSITION        const
       FALLBACK_RULE_COMPOSITION   │  FALLBACK_RULE_COMPOSITION      const
                                   │
                ┌─ src/llm/BossDialogue.gd (EXTEND) ───────┐
                │  pick_intent_async now reads:            │
                │   • player lead PC's autobattle rules    │
                │   • region learned_patterns              │
                │  emits: existing intent_id in a WIDER    │
                │   allowlist (fire_resist, focus_healer…) │
                └──────────────────────────────────────────┘
```

**Why this shape (Approach A + shared grammar const):**
- **Rejected B (shared module for both concerns):** mixing a player-facing composer with an enemy-facing adapter behind one API buys nothing beyond the shared grammar constant, which we can extract without merging modules.
- **Rejected C (grammar-as-nested-schema-in-`complete_json`):** the flat-schema stack in `LLMService.complete_json` is production-ready; extending it to nested schemas is scope creep. The existing `BossDialogue` pattern — emit as `String`, parse, second-pass validate — is the right idiom.
- **Shared grammar const** eliminates the only real DRY concern: describing the rule vocabulary to the LLM in prose. If Composer and Adapter drift on how they present the grammar, both features degrade. One const, both include it verbatim.

**Data flow — Composer (Item 20)**

```
[player types NL in overlay]
  → RuleComposer.compose_async(domain, prompt_text, current_rules_hint)
    → build LLMService.complete_json prompt
       preamble: AUTOBATTLE_GRAMMAR_DESCRIPTION (or AUTOGRIND_)
       body:     user text + current rules for reference
       schema:   SCHEMA_RULE_COMPOSITION = {rules_json: String, name: String, description: String}
    → LLMService.complete_json(prompt, schema, FALLBACK_RULE_COMPOSITION)
    → hard-validate emitted rules via AutobattleSystem.validate_rule
       (or AutogrindSystem.validate_rule — NEW helpers per §5)
    → RuleComposition {name, description, rules, errors, source: "llm"|"fallback"}
  → editor overlay shows preview
    → player Confirms → install_as_new_profile(...) OR replace_current_profile(...)
    → player Cancels  → discard
```

**Data flow — Learning Monsters (Item 27)**

```
[phase transition or encounter setup]
  → BattleManager._update_boss_dialogue_phase  (BM 6154, existing)
    → BossDialogue.pick_intent   (deterministic — existing)
      stashes combatant.set_meta("llm_intent", intent_id)
    → BattleManager._refine_boss_intent_async  (existing)
      → build BossIntentContext (EXTEND — add player_rule_summary + learned_patterns)
      → BossDialogue.pick_intent_async(ctx)
        → LLMService.complete_json(prompt, SCHEMA_BOSS_INTENT, FALLBACK_BOSS_INTENT)
        → validate against WIDENED intent allowlist (existing 3 + 6 new — §4)
        → override llm_intent on combatant meta (guarded by phase-stale check)
  → next _make_ai_decision consumes llm_intent via _bias_by_intent
    (existing seam; 6 sites scale weighted rolls, never pick abilities)
  → emit boss_taunt for player-visible narration (existing signal)
```

**Key non-invariant:** the LLM never names an ability, a rule, a target, or a story flag. Composer output is hard-validated against the grammar and rejected (fallback path) if invalid. Adapter output is one of ~9 authored intent tags; the deterministic ladder still picks the actual ability. This matches the `BattleManager.gd:6386` comment already in the codebase: *"LLM picks INTENT (a role direction), code chooses the exact ability. We never let the LLM name an ability."*

---

## 3. Item 20 — Rule Composer

### 3.1 UX

**Invocation.** Two on-ramps:
1. **Hotkey `K` (Kompose)** in `AutobattleGridEditor._input` at ~line 1719 (mirror the `KEY_I`/`KEY_E` pattern). Same key added to `AutogrindGridEditor._input`. Legend at `AutobattleGridEditor.gd:266` updated.
2. **Empty-grid splash.** `AutobattleGridEditor.setup()` line 181 always seeds a default rule via `_create_default_rule` — branch on `rules.size() == 0` **before** the seed to show a "Compose from prompt, browse templates, or start empty" splash. Same treatment in `AutogrindGridEditor`.

**Overlay UI.** Full-screen `Control` following the `_open_share_picker` pattern at `AutobattleGridEditor.gd:2641`:
- Text field for the natural-language prompt (single-line for v1; multi-line if the user hits Enter).
- "Compose" button (`A` on gamepad, Enter on keyboard).
- Cancel (`B` / Escape).
- While composing: show thinking indicator (existing pattern — reuse `set_thinking(true)` from `CutsceneDialogue`).
- On result: replace overlay with **preview panel** showing:
  - Composed rules in a read-only grid layout matching the target editor's presentation.
  - Auto-generated profile name + description at the top (editable).
  - Two toggles: "Install as new profile" (default) / "Replace current profile".
  - Confirm (`A`) / Cancel (`B`) / Regenerate (`R`).
- On errors (hard-validation failure): show the specific error messages and route to fallback UI (see §6).

**Player choice preserved.** The composer never writes to the persisted profile without an explicit Confirm. Regenerate is a first-class action; a slightly-off composition is often 30 seconds of iteration away.

### 3.2 Module

```gdscript
# src/llm/RuleComposer.gd  (new autoload — after LLMService, before BossDialogue)
extends Node
class_name RuleComposer

signal composition_ready(result: Dictionary)  # {name, description, rules: Array, errors: Array[String], source: String}
signal composition_failed(reason: String)     # "no_llm" | "invalid_json" | "grammar_errors" | "client_timeout"

const DOMAIN_AUTOBATTLE := "autobattle"
const DOMAIN_AUTOGRIND  := "autogrind"

func compose_async(domain: String, prompt_text: String, current_rules: Array = []) -> Dictionary:
    # 1. build prompt from DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION (or AUTOGRIND_) + user text
    # 2. LLMService.complete_json(prompt, SCHEMA_RULE_COMPOSITION, FALLBACK_RULE_COMPOSITION)
    # 3. parse rules_json; second-pass hard-validate via <domain>System.validate_rule
    # 4. return {name, description, rules, errors, source}
    ...

func has_llm() -> bool:
    # gates the hotkey/splash; false → fallback UI (template picker)
    ...
```

### 3.3 Prompt shape

`DialoguePrompts.build_rule_composition(domain, user_text, current_rules)` returns a prompt like:

```
You are a rule authoring assistant for a JRPG's autobattle system.

[AUTOBATTLE_GRAMMAR_DESCRIPTION or AUTOGRIND_GRAMMAR_DESCRIPTION verbatim]

Current rules (for reference; may be empty):
<compact JSON of current_rules>

Player intent:
<user_text>

Emit a JSON object with fields:
  name: short (3-6 words), snake-case-friendly, describing the strategy
  description: 1 sentence, in-character
  rules_json: the FULL rule list, as a JSON string. Each rule is
    {conditions: [...], actions: [...], enabled: true}
    conditions and actions must use only the verbs listed above.

Only emit the JSON. No commentary.
```

The **grammar description constant** enumerates every condition type, operator, action type, target type, and gives 1-2 canonical examples per domain — a static string, no dynamic assembly. That's the surface the LLM must respect.

### 3.4 Schema (flat, LLM-emit form)

```gdscript
# in src/llm/DialoguePrompts.gd
const SCHEMA_RULE_COMPOSITION := {
    "name":        "String",
    "description": "String",
    "rules_json":  "String",   # nested structure encoded as a JSON string
}

const FALLBACK_RULE_COMPOSITION := {
    "name": "Draft — LLM unavailable",
    "description": "Curated fallback; edit or pick a template.",
    "rules_json": "[]",
}
```

**Why `rules_json: String` and not `rules: Array`?** `LLMService.complete_json` supports only flat top-level schemas — see `_type_matches` at `LLMService.gd:708`. Nested `Array[Dictionary]` isn't validatable. Emitting a JSON string, parsing it separately, and hard-validating the parsed structure via `<domain>System.validate_rule` is the existing pattern (mirrors `BossDialogue.pick_intent_async` for `BossIntentReply`).

### 3.5 Second-pass hard validation

New helper in each system:

```gdscript
# src/autobattle/AutobattleSystem.gd  (add near the interpreter chokepoints ~line 174-296)
func validate_rule(rule: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    if not rule.has("conditions"): errors.append("missing 'conditions'")
    if not rule.has("actions"):    errors.append("missing 'actions'")
    for c in rule.get("conditions", []):
        if not c.get("type", "") in CONDITION_TYPES: errors.append("unknown condition type: %s" % c.get("type",""))
        # ... op, target, id, status checks per condition kind
    for a in rule.get("actions", []):
        if not a.get("type","") in ACTION_TYPES: errors.append("unknown action type: %s" % a.get("type",""))
        # ... target/id/item checks per action kind
    return errors
```

**Symmetric with existing soft-validation** (the current interpreter warns and coerces at `AutobattleSystem.gd:295` / `:315` / `:372` / `:406`), but **hard** for translator output — Composer refuses to render a preview when errors exist and shows them in the fallback UI.

Same pattern for `AutogrindSystem.validate_rule`, keyed on that domain's grammar (party_hp_min / member_dead / stop_grinding / etc.).

### 3.6 UI hookup

- `AutobattleGridEditor.gd`: add `KEY_K` branch to `_input` ladder (~1719); add `rules.size() == 0` branch in `setup()` (~line 181) for the splash; update legend const at `:266`.
- `AutogrindGridEditor.gd`: same three edits, using the autogrind domain.
- New `src/ui/autobattle/RuleComposerOverlay.gd` + scene: text field + preview panel + accept/cancel/regen buttons. Follows the `_option_picker` sentinel pattern at `AutobattleGridEditor.gd:1611-1620` for input gating.
- Same overlay Node parameterized by `domain`; the UI text and grammar surface differ, structure identical.

### 3.7 Install flow

- **New profile (default):**
  - Autogrind: `AutogrindRuleTemplates.install_as_new_profile(dict_out_of_composer, AutogrindSystem)` — the existing template installer already handles this.
  - Autobattle: mirror the autogrind installer — `AutobattleSystem.install_composition_as_new_profile(composition)`. (Existing profile system supports multiple named profiles.)
- **Replace current:** `AutobattleSystem.set_character_script(character_id, composition.rules)` / autogrind equivalent. Persists via existing save paths.

---

## 4. Item 27 — Learning Monsters

### 4.1 Extension surface

Only two edits:
1. **`BossIntentContext.gd`** — add fields for player rule summary and region learned_patterns.
2. **`BossDialogue.pick_intent_async` prompt** — mention the player's rule shape; emit intents from a **widened allowlist**.

### 4.2 BossIntentContext extension

```gdscript
# src/battle/BossIntentContext.gd  (existing)
# ADD:
var player_lead_pc_rules: Array = []       # compact summary — top 3-5 rules for lead PC
var learned_patterns_counter: String = ""  # region's current counter_strategy string
var learned_patterns_sample: Dictionary = {}  # optional: top-N abilities from ability_frequency
```

Populated by `BattleManager._refine_boss_intent_async` (~BM 6247) from:
- Lead PC autobattle profile: `AutobattleSystem.get_character_script(lead_pc_id)`; **summarize** by keeping the first 3-5 rules (avoid prompt bloat — LLMContext budget is ~2KB per existing convention). Full rules never leave the process.
- Region patterns: `AutogrindSystem._determine_counter_strategy(learned_patterns[region_id])` — the returned string (`fire_resist`, `focus_healer`, `""`, etc.). Free — the function is already there.
- Sample: top 3 entries of `ability_frequency` for the region.

### 4.3 Widened intent allowlist

`_bias_by_intent(intent_id, masterite_type)` at `BattleManager.gd:6364` today tables `aggress`, `turtle`, `exploit_pattern` — returns empty otherwise. Widen with **6 new intent tags** that mirror the existing counter_strategy strings so the mapping is 1:1:

| intent_id | maps to counter_strategy | consumer (existing) |
|---|---|---|
| `fire_resist` | fire_resist | `_bias_by_intent` scales fire-vulnerability rolls; `_get_counter_action` (BM ~5698) picks resist-buff |
| `ice_resist` | ice_resist | same |
| `lightning_resist` | lightning_resist | same |
| `focus_healer` | focus_healer | `_bias_by_intent` scales `target_weight[healer]` up; `_get_counter_action` picks healer-target |
| `defense_boost` | defense_boost | scales `guard_bias` up |
| `rotate_aggro` | rotate_aggro | scales `target_switch_chance` up |

These intents already have counter-action recipes in `_get_counter_action` (BM ~5698). The intent tags just give the LLM (and the deterministic path) a named handle. **No new abilities. No new counter-actions.** Only new labels feeding existing multipliers.

### 4.4 Prompt shape

`DialoguePrompts.build_boss_intent_prompt` (existing at `SCHEMA_BOSS_INTENT`, `:76`) extended:

```
[existing boss persona + phase + party HP context...]

The player is running an autobattle strategy. Their lead character's top rules:
<player_lead_pc_rules — compact JSON, 3-5 entries>

Recent battle patterns in this region suggest they favor:
<learned_patterns_sample — top 3 abilities + region's counter_strategy hint>

Given the boss's persona and this context, pick ONE strategic intent from:
  aggress, turtle, exploit_pattern,
  fire_resist, ice_resist, lightning_resist,
  focus_healer, defense_boost, rotate_aggro

Emit {intent_id, reason, taunt} — a short in-character taunt that hints at the intent.
```

Existing `SCHEMA_BOSS_INTENT = {intent_id: String, reason: String, taunt: String}` at `DialoguePrompts.gd:76` covers this; extend `validate_boss_intent_reply` (existing) to accept the widened allowlist.

### 4.5 Scripted floor (LLM off)

Free — the deterministic path already exists:
1. `BossDialogue.pick_intent` (scripted, existing) picks from `boss_dialogue.json` scripted_intents based on phase + `conditions`.
2. If the boss's scripted_intents include entries with `conditions` that reference `learned_patterns_counter` (a small authored field, e.g. `conditions: [{learned_patterns_counter: "fire_resist"}]`), the scripted picker will pick the matching intent when patterns show fire-frequency.
3. Authors extend `data/boss_dialogue.json` to add scripted_intents for the widened tags.

**Concrete example** — `chancellor_mordaine`:

```json
{
  "scripted_intents": [
    { "id": "aggress", "conditions": [{"phase": 1}], "taunt_lines": [...] },
    { "id": "turtle", "conditions": [{"phase": 3}], "taunt_lines": [...] },
    { "id": "exploit_pattern", "conditions": [{"phase": 2}], "taunt_lines": [...] },

    { "id": "focus_healer",
      "conditions": [{"learned_patterns_counter": "focus_healer"}],
      "taunt_lines": ["I see now. Your cleric is the seam."] },
    { "id": "fire_resist",
      "conditions": [{"learned_patterns_counter": "fire_resist"}],
      "taunt_lines": ["You always burn me first. Not this time."] }
  ]
}
```

**Scripted floor picks the counter intent** with just a small authored data addition; LLM refine adds voice variety when it's on.

### 4.6 Scope

- **LLM-enabled bosses only:** the 5 currently in the allowlist (`chancellor_mordaine`, `pyrroth`, `glacius`, `voltharion`, `umbraxis`). Regular monsters keep deterministic `learned_patterns` → `_determine_counter_strategy` → `_get_counter_action` path — this already works and needs no change.
- **Follow-up:** extend `learns_from: ["autobattle_rules"]` as a new tag on regular monsters, invoking a scripted-only (no LLM call) adaptation similar in shape to `_maybe_apply_elemental_adaptation`. Deferred; not in v1.

---

## 5. Data schema additions

### 5.1 `data/boss_dialogue.json`

For each of the 5 opt-in bosses, extend `scripted_intents[]` with the 6 new intent tags. Each new scripted_intent needs:
- `id` — one of the widened allowlist tags.
- `conditions` — typically `[{learned_patterns_counter: "<matching string>"}]` and/or phase.
- `taunt_lines` — per-boss voiced lines (2-4 each, in-character).

Owner: cowir-ai for the schema shape, coordinate with cowir-story for the taunt voicing.

### 5.2 Boss dialogue integrity test

Extend `test/unit/test_boss_dialogue_data_integrity.gd`:
- Every intent_id resolves against the widened allowlist.
- Every scripted_intent has ≥1 taunt_line.
- `conditions[learned_patterns_counter]` (if present) matches one of the 7 `_determine_counter_strategy` return values.

### 5.3 Grammar description constants

New in `src/llm/DialoguePrompts.gd`:

```gdscript
const AUTOBATTLE_GRAMMAR_DESCRIPTION := """
Autobattle rules are evaluated top-to-bottom, first match wins. Each rule is:
  {conditions: [...], actions: [...], enabled: true}
Conditions (AND-chained):
  hp_percent, mp_percent, ap, has_status, enemy_hp_percent, ally_hp_percent, ...
Operators: <, <=, ==, >=, >, !=
Actions (executed in order, up to 4 per rule):
  attack, ability {id: <ability_id>}, item {id: <item_id>}, defer
Targets: lowest_hp_enemy, highest_hp_enemy, random_enemy, lowest_hp_ally, all_allies, self, ...
Ability IDs must match this character's known abilities. Item IDs must match party inventory.
Prefer specific over general; put fallback (always) rules last.
"""

const AUTOGRIND_GRAMMAR_DESCRIPTION := """
Autogrind rules control the whole party's grind session.
Conditions: party_hp_min, party_hp_avg, alive_count, member_dead, corruption, inventory_items, always
Actions: stop_grinding, heal_party, switch_profile {character_id, profile_index}
Same top-to-bottom first-match-wins semantics.
"""
```

Ability/item ID enumeration is **not** included in the constant — those would inflate the prompt. Instead the Composer prompt appends the *lead PC's* current known abilities and party inventory dynamically. This keeps the constant static (cacheable) while giving the LLM the specific vocabulary it needs.

---

## 6. Fallback path

**No fallback path may be silent.** Every degradation shows the player something.

### 6.1 Composer fallback

| Condition | UX |
|---|---|
| LLM disabled globally | Splash suppresses the "Compose" affordance; hotkey shows a one-line "AI helper off — enable in Settings → Dynamic Dialogue" toast (reuses `_flash_status` at `AutobattleGridEditor.gd:2820`) |
| No BYOK configured / backend not ready | Same toast; splash routes to template picker (autogrind) or profile picker (autobattle) |
| 6s timeout | Overlay swaps to "AI timed out — try again, or browse templates" |
| Invalid JSON / grammar errors | Preview panel replaced with error list; "Regenerate" button prominent; "Browse templates" fallback below |
| Web build | Composer feature hard-off, hotkey hidden, empty-grid splash shows template picker directly (Composer button omitted); tests assert this |

The **template picker is the universal fallback** — it always ships with 3 curated presets (autogrind) or per-job defaults (autobattle).

### 6.2 Adapter fallback

| Condition | Behavior |
|---|---|
| LLM disabled or backend unavailable | `BossDialogue.pick_intent` deterministic path picks from scripted_intents (per §4.5). Scripted taunt lines fire via existing `boss_taunt` signal. Zero UX regression. |
| Timeout on refine | `_refine_boss_intent_async` already tolerates cancellation (existing stale-phase guard at BM ~6270). Deterministic intent stands. |
| Invalid intent_id from LLM | `validate_boss_intent_reply` returns fallback; deterministic intent stands. |

Adapter fallback is fully covered by existing plumbing plus the widened scripted_intents in `boss_dialogue.json`.

---

## 7. Testing

Live-path tests use `FakeBackend` (already exists at `test/unit/test_llm_fake_backend.gd`).

| Test | Coverage |
|---|---|
| `test_rule_composer_live_path.gd` | Prime FakeBackend to return a valid composition; assert RuleComposer parses + validates + emits `composition_ready` |
| `test_rule_composer_grammar_lint.gd` | Feed intentionally-broken emit (unknown condition type, missing action, invalid target); assert hard-validation catches it and Composer emits `composition_failed("grammar_errors")` |
| `test_rule_composer_web_fallback.gd` | Stub `OS.has_feature("web") → true`; assert Composer's `has_llm()` returns false and hotkey/splash routes to template picker |
| `test_rule_composer_timeout.gd` | FakeBackend `hang()` mode; assert 6s client timeout resolves to fallback with `composition_failed("client_timeout")` |
| `test_autobattle_validate_rule.gd` | Direct calls to `AutobattleSystem.validate_rule` — valid rule → empty; each error class → specific message |
| `test_autogrind_validate_rule.gd` | Same for autogrind grammar |
| `test_boss_intent_widened_allowlist.gd` | Prime FakeBackend to return each of the 9 intent tags; assert `validate_boss_intent_reply` accepts them all; assert unknown tag → fallback |
| `test_boss_intent_uses_player_rules.gd` | Snapshot the prompt built by `_refine_boss_intent_async` after adding a lead PC autobattle rule set with fire-heavy actions; assert the prompt string contains the summarized rule shape |
| `test_boss_dialogue_data_integrity.gd` (extend) | Every intent_id in `boss_dialogue.json` resolves to the widened allowlist; every `learned_patterns_counter` condition matches a valid counter_strategy return value |
| `test_no_engine_has_singleton.gd` (existing) | Continue to enforce; both new modules use `/root/` autoload lookups |

Story-flag guardrail is unchanged: the boss data integrity test already asserts no consequence writes canonical story flags. Composer never touches flags at all.

---

## 8. Cross-huddle interfaces

**cowir-autogrind:**
- Need read-only `AutogrindSystem.get_current_rules(character_id) → Array` if not present (for the "current rules for reference" prompt context).
- Install path already there: `AutogrindRuleTemplates.install_as_new_profile(dict, AutogrindSystem)` — Composer output shape is identical.
- Wanted: a hook to force-refresh `AutogrindGridEditor` after Composer installs a profile (probably `set_autogrind_rules` already emits a signal — verify).
- No blocker to their queue; this is additive.

**cowir-battle:**
- `_bias_by_intent(intent_id, masterite_type)` at `BM 6364` gains 6 new intent tags mapped to existing counter_strategy multipliers. Zero new abilities, no changes to `_get_counter_action` (already at `BM 5698`), no changes to the deterministic ladder.
- `BossIntentContext.gd` gains 3 new fields (`player_lead_pc_rules`, `learned_patterns_counter`, `learned_patterns_sample`). Purely additive.
- `_refine_boss_intent_async` (~BM 6247) builds the context from `AutobattleSystem.get_character_script(lead_pc_id)` and `AutogrindSystem.learned_patterns[region_id]`. Read-only.
- Coordinate with cowir-battle on the taunt-voicing for the 6 new intent tags (or fold under cowir-story).

**cowir-cutscenes:**
- No engine change needed; existing `boss_taunt` signal renders the widened taunts.

**cowir-main:**
- One autoload addition (`RuleComposer` after `LLMService`, before `BossDialogue`). No conflict.
- One SettingsMenu row conceivable ("Rule Composer prompt style: terse / verbose") — deferred, YAGNI.

**cowir-music, cowir-sfx, cowir-sprites, cowir-overworld:** no touchpoints.

---

## 9. Sequencing

Phases below are contract-clean and independently mergeable — later phases assume earlier landed but don't retroactively require them.

1. **Grammar guardrail.** Add `AutobattleSystem.validate_rule` + `AutogrindSystem.validate_rule` + `AUTOBATTLE_GRAMMAR_DESCRIPTION` + `AUTOGRIND_GRAMMAR_DESCRIPTION` + tests. **Blocks nothing else if we skip Composer.**
2. **Widened intent tags.** Extend `_bias_by_intent` (BM ~6364) with the 6 new tags + `validate_boss_intent_reply` allowlist widening + `boss_dialogue.json` scripted_intents for those 6 tags on Mordaine as the test-bed. Regression tests. **Ships the Adapter's scripted floor.**
3. **Extend BossIntentContext + `_refine_boss_intent_async` prompt** with player rules + learned_patterns summary. **Ships the Adapter's LLM refine.**
4. **RuleComposer module + shared constants + prompt + schema + FakeBackend live-path tests.** No UI yet — module is testable in isolation.
5. **RuleComposerOverlay UI + `AutobattleGridEditor` hotkey/splash wiring.**
6. **`AutogrindGridEditor` hotkey/splash wiring** (same overlay parameterized).
7. **Extend the other 4 opt-in bosses (`pyrroth`, `glacius`, `voltharion`, `umbraxis`)** with the widened scripted_intents. Diff should mostly be copy-and-voice.

Each phase = one commit or a small stack. Feature branch: `feature/cowir-ai-rule-composer-adaptation-spec` for the spec doc itself; implementation branches spun as work lands.

---

## 10. Open questions / follow-ups (out of scope for v1)

- **Per-role model routing** (translator vs chat) — plumb `opts.model_override` through `LLMService._submit_and_wait` (currently no per-call model override on backends). Trigger only if v1 quality issues surface.
- **Extending `learns_from: ["autobattle_rules"]` to regular monsters** with a scripted-only adaptation (no LLM). Needs a sibling helper to `_maybe_apply_elemental_adaptation`.
- **One-rule Composer emit** (edit-in-place, not whole-grid). Trigger if players ask.
- **Composer explanation** — after Confirm, show a one-liner *"Why these rules: ..."* pulled from `description` field. Cheap; not required for v1 acceptance.
- **Voice input** — additive; hook the composer text field to any future speech input feature.
- **Analytics** — count Composer accept vs cancel vs regenerate to gauge quality. Deferred until user asks.

---

## Appendix A — Files touched

| File | Kind | Notes |
|---|---|---|
| `src/llm/RuleComposer.gd` | create | new autoload |
| `src/llm/BossDialogue.gd` | edit | extend `pick_intent_async` context building |
| `src/battle/BossIntentContext.gd` | edit | +3 fields |
| `src/battle/BattleManager.gd` | edit | `_bias_by_intent` widened allowlist (~6364); `_refine_boss_intent_async` context build (~6247) |
| `src/llm/DialoguePrompts.gd` | edit | grammar consts, composer prompt, composer schema/fallback, `validate_boss_intent_reply` widened |
| `src/autobattle/AutobattleSystem.gd` | edit | `validate_rule` helper; `install_composition_as_new_profile` helper |
| `src/autogrind/AutogrindSystem.gd` | edit | `validate_rule` helper; `get_current_rules(character_id)` helper if missing |
| `src/ui/autobattle/AutobattleGridEditor.gd` | edit | hotkey (~1719), empty-grid splash branch (~181), legend const (~266) |
| `src/ui/autogrind/AutogrindGridEditor.gd` | edit | same three edits, autogrind domain |
| `src/ui/autobattle/RuleComposerOverlay.gd` + scene | create | text field + preview + buttons, parameterized by domain |
| `project.godot` | edit | add `RuleComposer` autoload after `LLMService`, before `BossDialogue` |
| `data/boss_dialogue.json` | edit | extend scripted_intents with 6 new tags for each of the 5 opt-in bosses (Mordaine first as test-bed) |
| `test/unit/test_rule_composer_*.gd` | create | 4 tests per §7 |
| `test/unit/test_autobattle_validate_rule.gd` | create | grammar guardrail |
| `test/unit/test_autogrind_validate_rule.gd` | create | grammar guardrail |
| `test/unit/test_boss_intent_widened_allowlist.gd` | create | intent tag coverage |
| `test/unit/test_boss_intent_uses_player_rules.gd` | create | prompt-shape assertion |
| `test/unit/test_boss_dialogue_data_integrity.gd` | edit | widened allowlist |

Estimated new lines: **~600 (module + overlay) + ~400 (tests) + ~150 (data)**. No file shrinks meaningfully; the biggest single addition is the overlay scene + script.
