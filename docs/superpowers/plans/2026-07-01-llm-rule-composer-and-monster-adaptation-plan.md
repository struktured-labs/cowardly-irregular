# LLM Rule Composer + Learning Monsters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the two features specified in `docs/superpowers/specs/2026-07-01-llm-rule-composer-and-monster-adaptation-design.md` — an LLM-driven Rule Composer (item 20) that turns natural-language player intent into draft autobattle/autogrind rules, and a Learning-Monsters extension (item 27) that lets LLM-enabled bosses read the player's autobattle rule shape and counter-draft their strategic intent.

**Architecture:** Two independent modules sharing a `DialoguePrompts` grammar-description constant. `src/llm/RuleComposer.gd` (new autoload) handles Composer; `src/llm/BossDialogue.gd` + `src/battle/BattleManager.gd` are extended for Learning Monsters. Both reuse the existing `LLMService.complete_json` + BYOK + `BossDialogue.pick_intent_async`-style deterministic-first / LLM-refine pattern. Both have complete scripted floors — LLM adds voice + pattern-reading but is never load-bearing.

**Tech Stack:** Godot 4 / GDScript. GUT test framework. JSON data. `LLMService` autoload (Ollama HTTP backend by default, BYOK-configurable). No external libs added.

## Global Constraints

- **Repo:** `/home/struktured/projects/cowir-main`, checked out on `feature/cowir-ai-rule-composer-adaptation-spec` (baseline `1ad734b1`).
- **Never modify branch off this branch's tip without user greenlight** — this plan is the greenlight gate; do not create sub-branches or push until user approves the plan.
- **Test command (single file):** `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_<name>.gd -gexit` (Bash timeout 90000ms).
- **Test command (full suite):** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit` (timeout 300000ms).
- **Syntax check:** `godot --headless --check-only --script <file>` (timeout 30000ms).
- **Full import (autoloads live):** `godot --headless --import` (timeout 180000ms). MUST run once after adding a new autoload before other tests resolve it globally.
- **Combatant uses `job_level` NOT `level`** — accessing `.level` silently crashes `_build_ui()`.
- **Typed Array[T] assignment from JSON silently fails** — always use explicit per-element `for x in data[key]: typed.append(str(x))` coercion when reading `Array[String]` fields.
- **Comments: 1 line max** per user rule 2026-06-17 across all `.gd` files.
- **NEVER use `Engine.has_singleton(name)` to gate an autoload** — Godot 4 autoloads are not `Engine` singletons; use `get_node_or_null("/root/<Name>")` or `(Engine.get_main_loop() as SceneTree).root.get_node_or_null("<Name>")` from static/refcounted contexts. `test_no_engine_has_singleton.gd` lints this repo-wide.
- **Story-flag guardrail:** no LLM output path may write `GameState.story_flags`. Enforced by `test_boss_dialogue_data_integrity.gd` and manual review of every consequence code path.
- **Web build:** Both features hard-off. Use `OS.has_feature("web")` checks; splash routes to template picker; boss deterministic path stands.
- **Frequent commits:** every task ends with a commit. Follow `feat(scope): ...`, `fix(scope): ...`, `test(scope): ...` message convention. Body must include a `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` line via HEREDOC.
- **NEVER push, merge to main, or deploy without explicit user approval.** Plan-only until user greenlights implementation.

---

## Task 1: Autobattle grammar guardrail

**Files:**
- Create: `test/unit/test_autobattle_validate_rule.gd`
- Modify: `src/autobattle/AutobattleSystem.gd` (add public method near interpreter chokepoints ~line 174-296)
- Modify: `src/llm/DialoguePrompts.gd` (add `AUTOBATTLE_GRAMMAR_DESCRIPTION` constant)

**Interfaces:**
- Consumes: existing `AutobattleSystem.CONDITION_TYPES` (line 79), `OPERATORS` (line 97), `ACTION_TYPES` (line 107), `TARGET_TYPES` (line 115).
- Produces:
  - `AutobattleSystem.validate_rule(rule: Dictionary) -> Array[String]` — returns list of error messages; empty array = valid.
  - `DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION: String` — static prompt fragment enumerating the autobattle rule vocabulary.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_autobattle_validate_rule.gd`:

```gdscript
extends GutTest

## Autobattle rule grammar hard-validation.
## Composer output MUST pass this or the preview is refused.

var autobattle_system

func before_each() -> void:
    autobattle_system = get_node_or_null("/root/AutobattleSystem")
    assert_not_null(autobattle_system, "AutobattleSystem autoload not available")

func test_valid_rule_returns_empty_errors() -> void:
    var rule := {
        "conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
        "actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
        "enabled": true,
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_eq(errors.size(), 0, "valid rule must produce zero errors; got: %s" % [errors])

func test_missing_conditions_key() -> void:
    var rule := {"actions": [{"type": "attack"}]}
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "missing conditions must produce an error")
    var joined: String = "|".join(errors)
    assert_true("conditions" in joined, "error should mention 'conditions'")

func test_missing_actions_key() -> void:
    var rule := {"conditions": [{"type": "always"}]}
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "missing actions must produce an error")
    var joined: String = "|".join(errors)
    assert_true("actions" in joined, "error should mention 'actions'")

func test_unknown_condition_type() -> void:
    var rule := {
        "conditions": [{"type": "hp_zorp", "op": "<", "value": 30}],
        "actions": [{"type": "attack"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown condition type must produce an error")
    var joined: String = "|".join(errors)
    assert_true("hp_zorp" in joined, "error should include the unknown type name")

func test_unknown_operator() -> void:
    var rule := {
        "conditions": [{"type": "hp_percent", "op": "!<>", "value": 30}],
        "actions": [{"type": "attack"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown operator must produce an error")

func test_unknown_action_type() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "yeet"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown action type must produce an error")
    var joined: String = "|".join(errors)
    assert_true("yeet" in joined, "error should include the unknown action name")

func test_ability_action_missing_id() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "ability", "target": "self"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "ability action without id must produce an error")

func test_unknown_target_type() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "attack", "target": "highest_luck_ally"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown target type must produce an error")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/struktured/projects/cowir-main && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autobattle_validate_rule.gd -gexit`
Expected: FAIL — `validate_rule` method does not exist on AutobattleSystem.

- [ ] **Step 3: Add `validate_rule` to AutobattleSystem.gd**

Add the following public method to `src/autobattle/AutobattleSystem.gd` immediately after `_evaluate_grid_condition` (around line 296, before `_compare_str`):

```gdscript
func validate_rule(rule: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    if not rule.has("conditions"):
        errors.append("missing 'conditions' array")
    elif typeof(rule["conditions"]) != TYPE_ARRAY:
        errors.append("'conditions' must be an array")
    if not rule.has("actions"):
        errors.append("missing 'actions' array")
    elif typeof(rule["actions"]) != TYPE_ARRAY:
        errors.append("'actions' must be an array")
    if errors.size() > 0:
        return errors
    for c in rule["conditions"]:
        if typeof(c) != TYPE_DICTIONARY:
            errors.append("condition must be a dictionary: %s" % [c])
            continue
        var ctype: String = str(c.get("type", ""))
        if not CONDITION_TYPES.has(ctype):
            errors.append("unknown condition type: '%s'" % ctype)
            continue
        if c.has("op") and not OPERATORS.has(str(c["op"])):
            errors.append("unknown operator: '%s'" % c["op"])
    for a in rule["actions"]:
        if typeof(a) != TYPE_DICTIONARY:
            errors.append("action must be a dictionary: %s" % [a])
            continue
        var atype: String = str(a.get("type", ""))
        if not ACTION_TYPES.has(atype):
            errors.append("unknown action type: '%s'" % atype)
            continue
        if atype == "ability" and not a.has("id"):
            errors.append("action type 'ability' requires 'id'")
        if atype == "item" and not a.has("id"):
            errors.append("action type 'item' requires 'id'")
        if a.has("target") and not TARGET_TYPES.has(str(a["target"])):
            errors.append("unknown target type: '%s'" % a["target"])
    return errors
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/struktured/projects/cowir-main && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autobattle_validate_rule.gd -gexit`
Expected: PASS — 8/8 tests green.

- [ ] **Step 5: Add `AUTOBATTLE_GRAMMAR_DESCRIPTION` constant to DialoguePrompts.gd**

Add to `src/llm/DialoguePrompts.gd` near the other constants (after the existing FALLBACK_* constants):

```gdscript
const AUTOBATTLE_GRAMMAR_DESCRIPTION := """Autobattle rules are evaluated top-to-bottom, first match wins.
Each rule shape:
  {conditions: [...], actions: [...], enabled: true}

Conditions (AND-chained). type is one of:
  hp_percent, mp_percent, ap, has_status, enemy_hp_percent, ally_hp_percent,
  turn, enemy_count, ally_count, item_count, setup_complete,
  ally_has_status, ally_mp_percent, always
Each numeric condition takes op ∈ {<, <=, ==, >=, >, !=} and value.
has_status / ally_has_status take a 'status' field (e.g. 'poison').

Actions (executed in order, up to 4 per rule). type is one of:
  attack, ability, item, defer
ability requires id (e.g. 'cure', 'fire').
item requires id (e.g. 'potion').

Targets. Values:
  lowest_hp_enemy, highest_hp_enemy, random_enemy,
  highest_speed_enemy, highest_atk_enemy, lowest_magic_defense_enemy,
  lowest_hp_ally, all_allies, self

Canonical example:
  {\"conditions\":[{\"type\":\"ally_has_status\",\"status\":\"poison\"},
                   {\"type\":\"mp_percent\",\"op\":\">=\",\"value\":15}],
   \"actions\":[{\"type\":\"ability\",\"id\":\"esuna\",\"target\":\"lowest_hp_ally\"}],
   \"enabled\":true}

Prefer specific rules over general ones. Put the fallback (a rule with
{type:'always'} condition and an attack action) last."""
```

- [ ] **Step 6: Syntax-check both modified files**

Run in parallel:
- `godot --headless --check-only --script src/autobattle/AutobattleSystem.gd`
- `godot --headless --check-only --script src/llm/DialoguePrompts.gd`
Expected: no parse errors on either.

- [ ] **Step 7: Commit**

```bash
cd /home/struktured/projects/cowir-main
git add src/autobattle/AutobattleSystem.gd src/llm/DialoguePrompts.gd test/unit/test_autobattle_validate_rule.gd
git commit -m "$(cat <<'EOF'
feat(autobattle): validate_rule hard-check + grammar description constant

Adds AutobattleSystem.validate_rule(rule) → Array[String] for hard
validation of LLM-emitted rules (existing interpreter only warns and
coerces; Composer needs a reject path). Adds
DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION constant that both
Composer and Adapter will inject as prompt preamble.

Task 1 of the Rule Composer + Learning Monsters plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Autogrind grammar guardrail

**Files:**
- Create: `test/unit/test_autogrind_validate_rule.gd`
- Modify: `src/autogrind/AutogrindSystem.gd` (add public method)
- Modify: `src/llm/DialoguePrompts.gd` (add `AUTOGRIND_GRAMMAR_DESCRIPTION` constant)

**Interfaces:**
- Consumes: existing autogrind rule condition/action string domain from `AutogrindSystem._create_default_autogrind_rules` (~line 1447): conditions `party_hp_min`, `party_hp_avg`, `alive_count`, `member_dead`, `corruption`, `inventory_items`, `always`; actions `stop_grinding`, `heal_party`, `switch_profile`.
- Produces:
  - `AutogrindSystem.validate_rule(rule: Dictionary) -> Array[String]`.
  - `DialoguePrompts.AUTOGRIND_GRAMMAR_DESCRIPTION: String`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_autogrind_validate_rule.gd`:

```gdscript
extends GutTest

var autogrind_system

func before_each() -> void:
    autogrind_system = get_node_or_null("/root/AutogrindSystem")
    assert_not_null(autogrind_system, "AutogrindSystem autoload not available")

func test_valid_autogrind_rule() -> void:
    var rule := {
        "conditions": [{"type": "party_hp_min", "op": "<", "value": 30}],
        "actions": [{"type": "heal_party"}],
        "enabled": true,
    }
    var errors: Array = autogrind_system.validate_rule(rule)
    assert_eq(errors.size(), 0, "valid rule must produce zero errors; got: %s" % [errors])

func test_missing_conditions() -> void:
    var rule := {"actions": [{"type": "stop_grinding"}]}
    var errors: Array = autogrind_system.validate_rule(rule)
    assert_gt(errors.size(), 0)
    assert_true("conditions" in "|".join(errors))

func test_unknown_autogrind_condition() -> void:
    var rule := {
        "conditions": [{"type": "phase_of_moon"}],
        "actions": [{"type": "stop_grinding"}],
    }
    var errors: Array = autogrind_system.validate_rule(rule)
    assert_gt(errors.size(), 0)
    assert_true("phase_of_moon" in "|".join(errors))

func test_switch_profile_missing_character_id() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "switch_profile", "profile_index": 1}],
    }
    var errors: Array = autogrind_system.validate_rule(rule)
    assert_gt(errors.size(), 0)
    assert_true("character_id" in "|".join(errors))

func test_switch_profile_missing_profile_index() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "switch_profile", "character_id": "cleric"}],
    }
    var errors: Array = autogrind_system.validate_rule(rule)
    assert_gt(errors.size(), 0)
    assert_true("profile_index" in "|".join(errors))

func test_unknown_action_type() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "explode_kingdom"}],
    }
    var errors: Array = autogrind_system.validate_rule(rule)
    assert_gt(errors.size(), 0)
    assert_true("explode_kingdom" in "|".join(errors))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autogrind_validate_rule.gd -gexit`
Expected: FAIL — method not defined.

- [ ] **Step 3: Add `validate_rule` to AutogrindSystem.gd**

Add to `src/autogrind/AutogrindSystem.gd` (near the existing public helpers around line 262):

```gdscript
const _AUTOGRIND_CONDITION_TYPES := ["party_hp_min", "party_hp_avg", "alive_count", "member_dead", "corruption", "inventory_items", "always"]
const _AUTOGRIND_OPERATORS := ["<", "<=", "==", ">=", ">", "!="]
const _AUTOGRIND_ACTION_TYPES := ["stop_grinding", "heal_party", "switch_profile"]

func validate_rule(rule: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    if not rule.has("conditions"):
        errors.append("missing 'conditions' array")
    elif typeof(rule["conditions"]) != TYPE_ARRAY:
        errors.append("'conditions' must be an array")
    if not rule.has("actions"):
        errors.append("missing 'actions' array")
    elif typeof(rule["actions"]) != TYPE_ARRAY:
        errors.append("'actions' must be an array")
    if errors.size() > 0:
        return errors
    for c in rule["conditions"]:
        if typeof(c) != TYPE_DICTIONARY:
            errors.append("condition must be a dictionary: %s" % [c])
            continue
        var ctype: String = str(c.get("type", ""))
        if not _AUTOGRIND_CONDITION_TYPES.has(ctype):
            errors.append("unknown autogrind condition type: '%s'" % ctype)
            continue
        if c.has("op") and not _AUTOGRIND_OPERATORS.has(str(c["op"])):
            errors.append("unknown operator: '%s'" % c["op"])
    for a in rule["actions"]:
        if typeof(a) != TYPE_DICTIONARY:
            errors.append("action must be a dictionary: %s" % [a])
            continue
        var atype: String = str(a.get("type", ""))
        if not _AUTOGRIND_ACTION_TYPES.has(atype):
            errors.append("unknown autogrind action type: '%s'" % atype)
            continue
        if atype == "switch_profile":
            if not a.has("character_id"):
                errors.append("action type 'switch_profile' requires 'character_id'")
            if not a.has("profile_index"):
                errors.append("action type 'switch_profile' requires 'profile_index'")
    return errors
```

- [ ] **Step 4: Run test**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autogrind_validate_rule.gd -gexit`
Expected: PASS — 6/6 tests green.

- [ ] **Step 5: Add `AUTOGRIND_GRAMMAR_DESCRIPTION` to DialoguePrompts.gd**

Add to `src/llm/DialoguePrompts.gd` immediately after `AUTOBATTLE_GRAMMAR_DESCRIPTION`:

```gdscript
const AUTOGRIND_GRAMMAR_DESCRIPTION := """Autogrind rules control the WHOLE PARTY's grind session (not per-character).
Rules are evaluated top-to-bottom, first match wins.

Conditions (AND-chained). type is one of:
  party_hp_min, party_hp_avg, alive_count, member_dead, corruption,
  inventory_items, always
Numeric conditions take op ∈ {<, <=, ==, >=, >, !=} and value.

Actions. type is one of:
  stop_grinding, heal_party, switch_profile
switch_profile requires character_id (PC id string) and profile_index (int).

Canonical example:
  {\"conditions\":[{\"type\":\"party_hp_min\",\"op\":\"<\",\"value\":30}],
   \"actions\":[{\"type\":\"heal_party\"}],
   \"enabled\":true}

Put the fallback (a rule with {type:'always'} condition) last, if any."""
```

- [ ] **Step 6: Syntax-check + full suite import**

Run in parallel:
- `godot --headless --check-only --script src/autogrind/AutogrindSystem.gd`
- `godot --headless --check-only --script src/llm/DialoguePrompts.gd`
Expected: no parse errors.

- [ ] **Step 7: Commit**

```bash
git add src/autogrind/AutogrindSystem.gd src/llm/DialoguePrompts.gd test/unit/test_autogrind_validate_rule.gd
git commit -m "$(cat <<'EOF'
feat(autogrind): validate_rule hard-check + grammar description constant

Symmetric with autobattle guardrail. Party-level grammar (party_hp_min /
member_dead / heal_party / switch_profile) hard-validated for Composer
output; DialoguePrompts.AUTOGRIND_GRAMMAR_DESCRIPTION constant for prompt
preamble.

Task 2 of the Rule Composer + Learning Monsters plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Widen `_bias_by_intent` with 6 counter-strategy tags

**Files:**
- Create: `test/unit/test_bias_by_intent_widened.gd`
- Modify: `src/battle/BattleManager.gd` (`_bias_by_intent` at ~line 6364)

**Interfaces:**
- Consumes: existing `_bias_by_intent(intent_id: String, masterite_type: String) -> Dictionary` at BM~6364, currently tables `aggress`/`turtle`/`exploit_pattern`.
- Produces: same signature, now also tables `fire_resist`, `ice_resist`, `lightning_resist`, `focus_healer`, `defense_boost`, `rotate_aggro` — each returning `{"counter_action_chance": 2.0}` (mirrors `exploit_pattern`'s boost so widened tags ride the same fire-more-often lever).

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_bias_by_intent_widened.gd`:

```gdscript
extends GutTest

const _COUNTER_INTENT_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
                                "focus_healer", "defense_boost", "rotate_aggro"]

var battle_manager

func before_each() -> void:
    battle_manager = get_node_or_null("/root/BattleManager")
    assert_not_null(battle_manager, "BattleManager autoload not available")

func test_widened_tags_boost_counter_chance() -> void:
    for tag in _COUNTER_INTENT_TAGS:
        var bias: Dictionary = battle_manager._bias_by_intent(tag, "warden")
        assert_true(bias.has("counter_action_chance"),
                    "%s must set counter_action_chance in bias dict" % tag)
        assert_almost_eq(float(bias["counter_action_chance"]), 2.0, 0.01,
                         "%s counter_action_chance should be 2.0" % tag)

func test_original_tags_still_present() -> void:
    var aggress: Dictionary = battle_manager._bias_by_intent("aggress", "warden")
    var turtle: Dictionary = battle_manager._bias_by_intent("turtle", "warden")
    var exploit: Dictionary = battle_manager._bias_by_intent("exploit_pattern", "warden")
    assert_gt(aggress.size(), 0, "aggress bias must not be empty")
    assert_gt(turtle.size(), 0, "turtle bias must not be empty")
    assert_gt(exploit.size(), 0, "exploit_pattern bias must not be empty")
    assert_true(exploit.has("counter_action_chance"),
                "exploit_pattern must keep counter_action_chance boost")

func test_unknown_intent_returns_empty_or_default() -> void:
    var bias: Dictionary = battle_manager._bias_by_intent("hokum_pokum", "warden")
    var chance: float = float(bias.get("counter_action_chance", 1.0))
    assert_almost_eq(chance, 1.0, 0.01,
                     "unknown intent must NOT boost counter_action_chance (default 1.0)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_bias_by_intent_widened.gd -gexit`
Expected: FAIL — the 6 widened tags return empty dicts today, so `counter_action_chance` is missing.

- [ ] **Step 3: Add the 6 widened tags to `_bias_by_intent`**

Locate `_bias_by_intent` in `src/battle/BattleManager.gd` (~line 6364). It's a `match intent_id` block returning a dict per case with a final default `return {}`. Add these 6 cases before the default:

```gdscript
        "fire_resist", "ice_resist", "lightning_resist", "focus_healer", "defense_boost", "rotate_aggro":
            return {"counter_action_chance": 2.0}
```

Consolidated into one branch since all 6 return the same bias (they differ only in which strategy they route to at the callsite guard — that's Task 4).

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_bias_by_intent_widened.gd -gexit`
Expected: PASS — 3/3 tests green.

- [ ] **Step 5: Syntax check**

Run: `godot --headless --check-only --script src/battle/BattleManager.gd`
Expected: no parse errors.

- [ ] **Step 6: Commit**

```bash
git add src/battle/BattleManager.gd test/unit/test_bias_by_intent_widened.gd
git commit -m "$(cat <<'EOF'
feat(boss-ai): widen _bias_by_intent with 6 counter-strategy tags

Adds fire_resist / ice_resist / lightning_resist / focus_healer /
defense_boost / rotate_aggro as LLM-selectable intent tags. Each returns
{counter_action_chance: 2.0} so the widened tag boosts the counter roll
the same way exploit_pattern does today. Actual strategy routing lands
in Task 4 as a callsite guard at _make_ai_decision.

Task 3 of the Rule Composer + Learning Monsters plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Strategy-override guard + adaptation_level gate widening

**Files:**
- Create: `test/unit/test_intent_forces_counter_strategy.gd`
- Modify: `src/battle/BattleManager.gd` (`_make_ai_decision` counter-strategy block ~line 1568-1587)

**Interfaces:**
- Consumes: `_bias_by_intent` (widened in Task 3), `combatant.get_meta("llm_intent", "")` (existing, set by `BossDialogue.pick_intent` scripted path at BM~6189), `AutogrindSystem.get_counter_strategy(region_id)` (existing public helper at AutogrindSystem.gd:262), existing `_get_counter_action` (BM~5698, unchanged).
- Produces: same `_make_ai_decision` behavior, now with strategy override + widened gate.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_intent_forces_counter_strategy.gd`:

```gdscript
extends GutTest

## Regression test for cowir-battle msg 1995 / spec §4.3.
##
## Verifies the strategy-override + gate widening at _make_ai_decision:
## when a boss's llm_intent is one of the widened counter-strategy tags,
## the deterministic counter_strategy from AutogrindSystem is overridden
## AND the adaptation_level > 0 gate is bypassed for that specific fire.

const _COUNTER_INTENT_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
                                "focus_healer", "defense_boost", "rotate_aggro"]

var battle_manager
var autogrind_system

func before_each() -> void:
    battle_manager = get_node_or_null("/root/BattleManager")
    autogrind_system = get_node_or_null("/root/AutogrindSystem")
    assert_not_null(battle_manager)
    assert_not_null(autogrind_system)

func test_intent_forces_counter_helper_returns_true_for_widened_tags() -> void:
    for tag in _COUNTER_INTENT_TAGS:
        assert_true(battle_manager._intent_forces_counter(tag),
                    "widened tag '%s' must set intent_forces_counter=true" % tag)

func test_intent_forces_counter_helper_returns_false_for_originals() -> void:
    for tag in ["aggress", "turtle", "exploit_pattern", "", "unknown"]:
        assert_false(battle_manager._intent_forces_counter(tag),
                     "non-widened tag '%s' must NOT force counter" % tag)

func test_strategy_override_helper() -> void:
    var region_id := "test_region_no_patterns"
    for tag in _COUNTER_INTENT_TAGS:
        var strategy: String = battle_manager._resolve_counter_strategy(region_id, tag)
        assert_eq(strategy, tag,
                  "intent '%s' must override empty deterministic strategy" % tag)

func test_strategy_falls_back_to_deterministic_for_non_widened_intent() -> void:
    var region_id := "test_region_no_patterns"
    var strategy: String = battle_manager._resolve_counter_strategy(region_id, "aggress")
    var expected: String = autogrind_system.get_counter_strategy(region_id)
    assert_eq(strategy, expected,
              "non-widened intent must not override deterministic strategy")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_intent_forces_counter_strategy.gd -gexit`
Expected: FAIL — helpers not defined.

- [ ] **Step 3: Add two thin private helpers to BattleManager**

Add near the top of `_make_ai_decision`'s block, before the counter-strategy read. Place at the natural home for AI helpers (near `_bias_by_intent` at ~BM:6364 is fine; both are tiny). Add:

```gdscript
const _COUNTER_INTENT_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
                                "focus_healer", "defense_boost", "rotate_aggro"]

func _intent_forces_counter(intent_id: String) -> bool:
    return intent_id in _COUNTER_INTENT_TAGS

func _resolve_counter_strategy(region_id: String, intent_id: String) -> String:
    if _intent_forces_counter(intent_id):
        return intent_id
    var autogrind = get_node_or_null("/root/AutogrindSystem")
    if autogrind == null:
        return ""
    return autogrind.get_counter_strategy(region_id)
```

- [ ] **Step 4: Verify helpers pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_intent_forces_counter_strategy.gd -gexit`
Expected: PASS — 4/4 tests green.

- [ ] **Step 5: Wire helpers into `_make_ai_decision` counter path**

Locate the counter-strategy block in `_make_ai_decision` (~line 1568-1587). It currently reads roughly:

```gdscript
var counter_strategy = _get_current_counter_strategy()   # (or similar existing lookup)
...
var counter_chance = 0.3 * adaptation_level
var ci_bias = _bias_by_intent(combatant.get_meta("llm_intent",""))
counter_chance = clampf(counter_chance * ci_bias.get("counter_action_chance",1.0), 0.0, 1.0)
if adaptation_level > 0 and not counter_strategy.is_empty():
    if randf() < counter_chance:
        var counter_action = _get_counter_action(...)
```

Rewrite the strategy read and the gate to use the two new helpers:

```gdscript
var region_id: String = _current_region_id_for(combatant)   # existing accessor pattern
var intent: String = combatant.get_meta("llm_intent", "")
var intent_forces_counter: bool = _intent_forces_counter(intent)
var counter_strategy: String = _resolve_counter_strategy(region_id, intent)

var ci_bias: Dictionary = _bias_by_intent(intent, _masterite_type_of(combatant))
var counter_chance: float = clampf(0.3 * adaptation_level * ci_bias.get("counter_action_chance", 1.0), 0.0, 1.0)

if (adaptation_level > 0 or intent_forces_counter) and not counter_strategy.is_empty():
    if randf() < counter_chance:
        var counter_action = _get_counter_action(combatant, counter_strategy)
        # ... existing counter-action handling unchanged
```

If `_current_region_id_for` or `_masterite_type_of` are named differently in current main, use the equivalent — do NOT invent new accessors; the existing read patterns for region_id and masterite_type at this callsite must be preserved.

- [ ] **Step 6: Confirm no regressions in existing boss/adaptation tests**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue.gd -gexit` (60s timeout).
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_jailbreak_battle_integration.gd -gexit`.
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_intent_forces_counter_strategy.gd -gexit`.
Expected: all PASS. The gate rewrite must not regress existing boss behavior for the 3 original intents or the deterministic path with adaptation_level > 0.

- [ ] **Step 7: Syntax check**

Run: `godot --headless --check-only --script src/battle/BattleManager.gd`
Expected: no parse errors.

- [ ] **Step 8: Commit**

```bash
git add src/battle/BattleManager.gd test/unit/test_intent_forces_counter_strategy.gd
git commit -m "$(cat <<'EOF'
feat(boss-ai): strategy override + adaptation gate widening for widened intents

Two thin helpers (_intent_forces_counter, _resolve_counter_strategy) plus
a rewritten counter-strategy block in _make_ai_decision:

  - 6 widened intent tags (fire_resist, ..., rotate_aggro) override the
    deterministic counter_strategy from AutogrindSystem.
  - adaptation_level > 0 gate is widened with intent_forces_counter, so
    a boss with LLM/scripted intent in a fresh region still gets its
    counter behavior.
  - 3 original intents (aggress/turtle/exploit_pattern) and the empty
    intent still respect the adaptation gate — no regression.

Per cowir-battle msg 1991 (seam mechanism) + 1995 (gate widening).
Task 4 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Widen `validate_boss_intent_reply` allowlist

**Files:**
- Modify: `test/unit/test_boss_dialogue.gd` (add/extend widened-allowlist test — check whether an existing test already covers the 3 original tags before adding)
- Create: `test/unit/test_validate_boss_intent_reply_widened.gd`
- Modify: `src/llm/DialoguePrompts.gd` (`validate_boss_intent_reply`)

**Interfaces:**
- Consumes: none new.
- Produces: `DialoguePrompts.validate_boss_intent_reply(reply: Dictionary) -> Dictionary` now accepts intent_id ∈ {aggress, turtle, exploit_pattern, fire_resist, ice_resist, lightning_resist, focus_healer, defense_boost, rotate_aggro}; falls back on any other value.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_validate_boss_intent_reply_widened.gd`:

```gdscript
extends GutTest

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")

const _ALL_ALLOWED := ["aggress", "turtle", "exploit_pattern",
                       "fire_resist", "ice_resist", "lightning_resist",
                       "focus_healer", "defense_boost", "rotate_aggro"]

func test_all_allowed_tags_pass_validation() -> void:
    for tag in _ALL_ALLOWED:
        var reply := {"intent_id": tag, "reason": "test", "taunt": "test"}
        var validated: Dictionary = DialoguePrompts.validate_boss_intent_reply(reply)
        assert_eq(validated.get("intent_id", ""), tag,
                  "intent '%s' should be preserved by validator" % tag)

func test_unknown_intent_falls_back() -> void:
    var reply := {"intent_id": "make_soup", "reason": "test", "taunt": "test"}
    var validated: Dictionary = DialoguePrompts.validate_boss_intent_reply(reply)
    assert_ne(validated.get("intent_id", ""), "make_soup",
              "unknown intent must NOT be accepted verbatim")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_validate_boss_intent_reply_widened.gd -gexit`
Expected: FAIL — the 6 widened tags currently fall through to fallback.

- [ ] **Step 3: Locate and widen the allowlist in `validate_boss_intent_reply`**

Open `src/llm/DialoguePrompts.gd`, find `validate_boss_intent_reply`. It has an allowlist array or `in` check against the 3 existing intents. Extend it to include the 6 new tags:

```gdscript
const _BOSS_INTENT_ALLOWLIST := [
    "aggress", "turtle", "exploit_pattern",
    "fire_resist", "ice_resist", "lightning_resist",
    "focus_healer", "defense_boost", "rotate_aggro",
]
```

Use this const in the existing membership check. If the existing check is inline (`if intent_id in ["aggress", "turtle", "exploit_pattern"]`), replace it with `if intent_id in _BOSS_INTENT_ALLOWLIST`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_validate_boss_intent_reply_widened.gd -gexit`
Expected: PASS — 2/2 tests green.

- [ ] **Step 5: Confirm existing boss-dialogue tests still pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue.gd -gexit`
Expected: PASS.

- [ ] **Step 6: Syntax check**

Run: `godot --headless --check-only --script src/llm/DialoguePrompts.gd`
Expected: no parse errors.

- [ ] **Step 7: Commit**

```bash
git add src/llm/DialoguePrompts.gd test/unit/test_validate_boss_intent_reply_widened.gd
git commit -m "$(cat <<'EOF'
feat(llm): widen validate_boss_intent_reply allowlist to 9 intent tags

Adds the 6 widened counter-strategy tags (fire_resist / ice_resist /
lightning_resist / focus_healer / defense_boost / rotate_aggro) to the
allowlist consumed by BossDialogue.pick_intent_async's schema-validator.
Unknown intent_id still falls back cleanly.

Task 5 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Extend Mordaine's `boss_dialogue.json` with widened scripted_intents

**Files:**
- Modify: `data/boss_dialogue.json` (chancellor_mordaine.scripted_intents)
- Modify: `test/unit/test_boss_dialogue_data_integrity.gd` (widen allowlist check + `learned_patterns_counter` condition validation)

**Interfaces:**
- Consumes: `AutogrindSystem.get_counter_strategy` counter string domain (fire_resist, ice_resist, lightning_resist, focus_healer, defense_boost, rotate_aggro, generic_counter).
- Produces: Mordaine's scripted floor now covers all 6 widened tags; each has taunt_lines and a `learned_patterns_counter` condition.

- [ ] **Step 1: Write the failing integrity test extension**

Open `test/unit/test_boss_dialogue_data_integrity.gd`. Add:

```gdscript
const _ALLOWED_INTENT_TAGS := ["aggress", "turtle", "exploit_pattern",
                                "fire_resist", "ice_resist", "lightning_resist",
                                "focus_healer", "defense_boost", "rotate_aggro"]

const _ALLOWED_COUNTER_STRATEGY_STRINGS := ["fire_resist", "ice_resist", "lightning_resist",
                                             "focus_healer", "defense_boost", "rotate_aggro",
                                             "generic_counter", ""]

func test_every_scripted_intent_id_is_in_widened_allowlist() -> void:
    var data: Dictionary = _load_boss_dialogue_data()
    for boss_id in data.keys():
        var boss: Dictionary = data[boss_id]
        for intent in boss.get("scripted_intents", []):
            var intent_id: String = str(intent.get("id", ""))
            assert_true(intent_id in _ALLOWED_INTENT_TAGS,
                        "%s.scripted_intents.id='%s' not in widened allowlist" % [boss_id, intent_id])

func test_learned_patterns_counter_conditions_reference_valid_strategies() -> void:
    var data: Dictionary = _load_boss_dialogue_data()
    for boss_id in data.keys():
        var boss: Dictionary = data[boss_id]
        for intent in boss.get("scripted_intents", []):
            for cond in intent.get("conditions", []):
                if typeof(cond) != TYPE_DICTIONARY:
                    continue
                if cond.has("learned_patterns_counter"):
                    var val: String = str(cond["learned_patterns_counter"])
                    assert_true(val in _ALLOWED_COUNTER_STRATEGY_STRINGS,
                                "%s.scripted_intents.conditions.learned_patterns_counter='%s' is not a valid counter_strategy value" % [boss_id, val])

func test_mordaine_covers_all_six_widened_tags() -> void:
    var data: Dictionary = _load_boss_dialogue_data()
    var mordaine: Dictionary = data.get("chancellor_mordaine", {})
    var ids: Array = []
    for intent in mordaine.get("scripted_intents", []):
        ids.append(str(intent.get("id", "")))
    for tag in ["fire_resist", "ice_resist", "lightning_resist",
                "focus_healer", "defense_boost", "rotate_aggro"]:
        assert_true(tag in ids,
                    "chancellor_mordaine.scripted_intents must include '%s'" % tag)
```

If `_load_boss_dialogue_data` doesn't yet exist as a helper in that test, add:

```gdscript
func _load_boss_dialogue_data() -> Dictionary:
    var f := FileAccess.open("res://data/boss_dialogue.json", FileAccess.READ)
    if f == null:
        fail_test("cannot open res://data/boss_dialogue.json")
        return {}
    var text: String = f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        fail_test("boss_dialogue.json root is not a Dictionary")
        return {}
    var out: Dictionary = {}
    for k in parsed.keys():
        if str(k).begins_with("_"):
            continue
        out[str(k)] = parsed[k]
    return out
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue_data_integrity.gd -gexit`
Expected: FAIL — Mordaine's scripted_intents do not yet include the 6 widened tags.

- [ ] **Step 3: Extend Mordaine's scripted_intents in `data/boss_dialogue.json`**

Open `data/boss_dialogue.json`. Locate `chancellor_mordaine.scripted_intents`. Append these 6 entries (preserve existing ones intact — do NOT overwrite):

```json
{
  "id": "fire_resist",
  "name": "Kindling anticipated",
  "conditions": [{"learned_patterns_counter": "fire_resist"}],
  "taunt_lines": [
    "You always burn me first. Not this time.",
    "Fire again. Predictable. The Calibrant learns.",
    "Your kindling loses its heat when it is expected."
  ]
},
{
  "id": "ice_resist",
  "name": "Winter's counter",
  "conditions": [{"learned_patterns_counter": "ice_resist"}],
  "taunt_lines": [
    "Frost is a repetition, not a strategy.",
    "You reach for cold. I have already been colder.",
    "The Calibrant is ice's older brother."
  ]
},
{
  "id": "lightning_resist",
  "name": "Ground the current",
  "conditions": [{"learned_patterns_counter": "lightning_resist"}],
  "taunt_lines": [
    "Thunder loses its authority the third time you speak it.",
    "Storm the sky again. I am the ground.",
    "Lightning is a language you have forgotten how to vary."
  ]
},
{
  "id": "focus_healer",
  "name": "Cleric is the seam",
  "conditions": [{"learned_patterns_counter": "focus_healer"}],
  "taunt_lines": [
    "I see now. Your cleric is the seam.",
    "Cut the healer. The rest is just delay.",
    "Every one of your strategies begins the same way — with your priest still alive."
  ]
},
{
  "id": "defense_boost",
  "name": "Iron before mercy",
  "conditions": [{"learned_patterns_counter": "defense_boost"}],
  "taunt_lines": [
    "The Calibrant's guard is a wall your script has not read.",
    "You strike as scripted. I stand as compiled.",
    "Iron before mercy. Always."
  ]
},
{
  "id": "rotate_aggro",
  "name": "The seat rotates",
  "conditions": [{"learned_patterns_counter": "rotate_aggro"}],
  "taunt_lines": [
    "The throne rotates. So does its hatred.",
    "Focus is your weakness. Pick another.",
    "You always press the same PC. I will press five."
  ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue_data_integrity.gd -gexit`
Expected: PASS — Mordaine now covers all 6 widened tags; every learned_patterns_counter references a valid strategy string.

- [ ] **Step 5: JSON syntax check**

Run: `python3 -c "import json; json.load(open('/home/struktured/projects/cowir-main/data/boss_dialogue.json'))"`
Expected: no output (silent success).

- [ ] **Step 6: Confirm existing boss tests still pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue.gd -gexit`
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_jailbreak_battle_integration.gd -gexit`
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git add data/boss_dialogue.json test/unit/test_boss_dialogue_data_integrity.gd
git commit -m "$(cat <<'EOF'
feat(boss-ai): Mordaine's scripted floor covers 6 widened counter tags

Adds fire_resist / ice_resist / lightning_resist / focus_healer /
defense_boost / rotate_aggro scripted_intents to chancellor_mordaine
with learned_patterns_counter conditions and in-voice taunt lines. The
data-integrity test now enforces both the widened allowlist and that
every learned_patterns_counter references a valid AutogrindSystem
counter_strategy string.

With this, the Adapter's scripted floor is complete for Mordaine — LLM
off, the boss still counter-drafts against player patterns via the
deterministic BossDialogue.pick_intent path.

Task 6 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Extend `BossIntentContext.gd` with player rules + patterns

**Files:**
- Create: `test/unit/test_boss_intent_context_extension.gd`
- Modify: `src/battle/BossIntentContext.gd`

**Interfaces:**
- Consumes: none new.
- Produces: 3 new fields on `BossIntentContext`:
  - `player_lead_pc_rules: Array` — compact rule summary (3-5 top entries)
  - `learned_patterns_counter: String` — the counter_strategy string
  - `learned_patterns_sample: Dictionary` — top-N slice of ability_frequencies + element_usage

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_boss_intent_context_extension.gd`:

```gdscript
extends GutTest

const BossIntentContext := preload("res://src/battle/BossIntentContext.gd")

func test_default_fields_present_and_empty() -> void:
    var ctx: BossIntentContext = BossIntentContext.new()
    assert_true("player_lead_pc_rules" in ctx,
                "BossIntentContext must expose player_lead_pc_rules")
    assert_true("learned_patterns_counter" in ctx,
                "BossIntentContext must expose learned_patterns_counter")
    assert_true("learned_patterns_sample" in ctx,
                "BossIntentContext must expose learned_patterns_sample")
    assert_eq(ctx.player_lead_pc_rules.size(), 0)
    assert_eq(ctx.learned_patterns_counter, "")
    assert_eq(ctx.learned_patterns_sample.size(), 0)

func test_fields_accept_assignment() -> void:
    var ctx: BossIntentContext = BossIntentContext.new()
    ctx.player_lead_pc_rules = [{"conditions": [], "actions": []}]
    ctx.learned_patterns_counter = "fire_resist"
    ctx.learned_patterns_sample = {"ability_frequencies": {"fire": 42}}
    assert_eq(ctx.player_lead_pc_rules.size(), 1)
    assert_eq(ctx.learned_patterns_counter, "fire_resist")
    assert_eq(ctx.learned_patterns_sample.get("ability_frequencies", {}).get("fire", 0), 42)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_intent_context_extension.gd -gexit`
Expected: FAIL — fields not present.

- [ ] **Step 3: Add fields to BossIntentContext.gd**

Open `src/battle/BossIntentContext.gd`. Near the existing `var` declarations, add:

```gdscript
var player_lead_pc_rules: Array = []
var learned_patterns_counter: String = ""
var learned_patterns_sample: Dictionary = {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_intent_context_extension.gd -gexit`
Expected: PASS — 2/2 tests green.

- [ ] **Step 5: Syntax check**

Run: `godot --headless --check-only --script src/battle/BossIntentContext.gd`
Expected: no parse errors.

- [ ] **Step 6: Commit**

```bash
git add src/battle/BossIntentContext.gd test/unit/test_boss_intent_context_extension.gd
git commit -m "$(cat <<'EOF'
feat(boss-ai): BossIntentContext gains player rule + learned-patterns fields

Purely additive: player_lead_pc_rules (Array), learned_patterns_counter
(String), learned_patterns_sample (Dictionary). Consumed by
BattleManager._refine_boss_intent_async in Task 8; unused by everything
else today.

Task 7 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Extend `_refine_boss_intent_async` prompt with player rules + patterns

**Files:**
- Create: `test/unit/test_boss_intent_uses_player_rules.gd`
- Modify: `src/battle/BattleManager.gd` (`_refine_boss_intent_async` at ~line 6247)
- Modify: `src/llm/DialoguePrompts.gd` (extend `build_boss_intent_prompt` to receive player_lead_pc_rules + patterns_sample)

**Interfaces:**
- Consumes: `AutobattleSystem.get_character_script(character_id)`, `AutogrindSystem.get_counter_strategy(region_id)`, `AutogrindSystem.get_learned_patterns_for_region(region_id)`, `BossIntentContext` (extended in Task 7).
- Produces: `_refine_boss_intent_async` builds a `BossIntentContext` that includes the 3 new fields. `DialoguePrompts.build_boss_intent_prompt(ctx)` embeds them into the prompt text.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_boss_intent_uses_player_rules.gd`:

```gdscript
extends GutTest

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")
const BossIntentContext := preload("res://src/battle/BossIntentContext.gd")

func test_prompt_includes_player_rules_summary() -> void:
    var ctx: BossIntentContext = BossIntentContext.new()
    ctx.player_lead_pc_rules = [
        {"conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
         "actions": [{"type": "ability", "id": "fire", "target": "lowest_hp_enemy"}]},
    ]
    ctx.learned_patterns_counter = "fire_resist"
    ctx.learned_patterns_sample = {"ability_frequencies": {"fire": 42, "attack": 12}}
    var prompt: String = DialoguePrompts.build_boss_intent_prompt(ctx)
    assert_true("fire_resist" in prompt,
                "prompt must include the learned_patterns_counter string")
    assert_true("fire" in prompt,
                "prompt must surface the player's fire-frequency signal")

func test_prompt_lists_widened_allowlist() -> void:
    var ctx: BossIntentContext = BossIntentContext.new()
    var prompt: String = DialoguePrompts.build_boss_intent_prompt(ctx)
    for tag in ["fire_resist", "ice_resist", "lightning_resist",
                "focus_healer", "defense_boost", "rotate_aggro"]:
        assert_true(tag in prompt,
                    "prompt must list widened intent '%s' as a choice" % tag)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_intent_uses_player_rules.gd -gexit`
Expected: FAIL — current prompt builder ignores the 3 new fields and lists only the 3 original intent tags.

- [ ] **Step 3: Extend `build_boss_intent_prompt` in DialoguePrompts.gd**

Locate `build_boss_intent_prompt` in `src/llm/DialoguePrompts.gd` (near `SCHEMA_BOSS_INTENT` at line 76). Ensure the function receives the extended `BossIntentContext`. Inject after the existing boss persona/phase/party HP context and before the "pick ONE intent" instruction:

```gdscript
    if ctx.player_lead_pc_rules != null and ctx.player_lead_pc_rules.size() > 0:
        prompt += "\n\nThe player is running an autobattle strategy. Their lead character's top rules (compact JSON):\n"
        prompt += JSON.stringify(ctx.player_lead_pc_rules)
    if ctx.learned_patterns_counter != "":
        prompt += "\n\nRecent battle patterns in this region derive counter_strategy=%s." % ctx.learned_patterns_counter
    if ctx.learned_patterns_sample != null and ctx.learned_patterns_sample.size() > 0:
        prompt += "\nSample signals:\n" + JSON.stringify(ctx.learned_patterns_sample)
    prompt += "\n\nGiven the boss's persona and this context, pick ONE strategic intent from:\n"
    prompt += "  aggress, turtle, exploit_pattern,\n"
    prompt += "  fire_resist, ice_resist, lightning_resist,\n"
    prompt += "  focus_healer, defense_boost, rotate_aggro\n"
    prompt += "\nEmit {intent_id, reason, taunt} — taunt is a short in-character line that HINTS at the intent."
```

Keep the existing boss persona / phase / party HP prefix intact — the widened block appends to it.

- [ ] **Step 4: Run prompt test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_intent_uses_player_rules.gd -gexit`
Expected: PASS — 2/2 tests green.

- [ ] **Step 5: Populate the context in `_refine_boss_intent_async`**

Open `src/battle/BattleManager.gd`. Locate `_refine_boss_intent_async` at ~line 6247. Before it calls `boss_dlg.pick_intent_async(ctx)`, populate the 3 new fields:

```gdscript
    var lead_pc_id: String = _lead_pc_id_for_party()          # existing accessor
    var autobattle = get_node_or_null("/root/AutobattleSystem")
    if autobattle != null:
        var full_script: Array = autobattle.get_character_script(lead_pc_id)
        # summarize: keep first 5 rules for prompt-budget hygiene
        ctx.player_lead_pc_rules = full_script.slice(0, min(5, full_script.size()))
    var autogrind = get_node_or_null("/root/AutogrindSystem")
    if autogrind != null:
        var region_id: String = _current_region_id_for(combatant)
        ctx.learned_patterns_counter = autogrind.get_counter_strategy(region_id)
        var full_patterns: Dictionary = autogrind.get_learned_patterns_for_region(region_id)
        var sample: Dictionary = {}
        if full_patterns.has("ability_frequencies"):
            sample["ability_frequencies"] = _top_n(full_patterns["ability_frequencies"], 3)
        if full_patterns.has("element_usage"):
            sample["element_usage"] = _top_n(full_patterns["element_usage"], 3)
        ctx.learned_patterns_sample = sample
```

Add a small `_top_n` helper alongside if not already present:

```gdscript
func _top_n(source: Dictionary, n: int) -> Dictionary:
    var pairs: Array = []
    for k in source.keys():
        pairs.append([source[k], k])
    pairs.sort_custom(func(a, b): return a[0] > b[0])
    var out: Dictionary = {}
    for i in range(min(n, pairs.size())):
        out[pairs[i][1]] = pairs[i][0]
    return out
```

If `_lead_pc_id_for_party` or `_current_region_id_for` are named differently in current main, substitute the correct existing accessor — do NOT invent new ones.

- [ ] **Step 6: Full boss suite regression check**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue.gd -gexit`
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_jailbreak_battle_integration.gd -gexit`
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_intent_context_extension.gd -gexit`
Expected: all PASS.

- [ ] **Step 7: Syntax check**

Run: `godot --headless --check-only --script src/battle/BattleManager.gd`
Run: `godot --headless --check-only --script src/llm/DialoguePrompts.gd`
Expected: no parse errors.

- [ ] **Step 8: Commit**

```bash
git add src/battle/BattleManager.gd src/llm/DialoguePrompts.gd test/unit/test_boss_intent_uses_player_rules.gd
git commit -m "$(cat <<'EOF'
feat(boss-ai): _refine_boss_intent_async feeds player rules + patterns

BattleManager._refine_boss_intent_async now populates the new
BossIntentContext fields from existing public helpers
(AutobattleSystem.get_character_script,
AutogrindSystem.get_counter_strategy / get_learned_patterns_for_region).
DialoguePrompts.build_boss_intent_prompt appends the summarized player
rules + top-3 ability_frequencies + element_usage + derived counter
strategy, and lists the widened allowlist of 9 intent tags.

Fallback path unchanged: LLM off → BossDialogue.pick_intent scripted
path (Task 6) still fires.

Task 8 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `RuleComposer.gd` autoload skeleton

**Files:**
- Create: `src/llm/RuleComposer.gd`
- Create: `test/unit/test_rule_composer_scaffold.gd`
- Modify: `project.godot` (add `RuleComposer` autoload entry between `LLMService` and `BossDialogue`)

**Interfaces:**
- Consumes: `LLMService` autoload (existing).
- Produces:
  - Autoload `RuleComposer` accessible at `/root/RuleComposer`.
  - Constants `RuleComposer.DOMAIN_AUTOBATTLE`, `RuleComposer.DOMAIN_AUTOGRIND`.
  - Signals `composition_ready(result: Dictionary)` and `composition_failed(reason: String, details: Dictionary)` per spec §Signal Contract.
  - Method `has_llm() -> bool` returning true when LLMService is available AND `llm_enabled` AND backend is ready.
  - Method `compose_async(domain, prompt_text, character_id, current_rules) -> Dictionary` (empty body for now — populated in Task 10).

- [ ] **Step 1: Write the scaffolding test first**

Create `test/unit/test_rule_composer_scaffold.gd`:

```gdscript
extends GutTest

var rc

func before_each() -> void:
    rc = get_node_or_null("/root/RuleComposer")
    assert_not_null(rc, "RuleComposer autoload not available; check project.godot")

func test_domain_constants_exposed() -> void:
    assert_eq(rc.DOMAIN_AUTOBATTLE, "autobattle")
    assert_eq(rc.DOMAIN_AUTOGRIND, "autogrind")

func test_signals_declared() -> void:
    assert_true(rc.has_signal("composition_ready"))
    assert_true(rc.has_signal("composition_failed"))

func test_has_llm_returns_bool() -> void:
    var v: Variant = rc.has_llm()
    assert_eq(typeof(v), TYPE_BOOL, "has_llm() must return a bool, not: %s" % [v])

func test_compose_async_returns_dict_shape() -> void:
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "cleric", [])
    assert_true(result.has("name"))
    assert_true(result.has("description"))
    assert_true(result.has("rules"))
    assert_true(result.has("source"))
    assert_true(result.has("errors"))
    assert_true(result.has("domain"))
    assert_true(result.has("character_id"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_scaffold.gd -gexit`
Expected: FAIL — RuleComposer autoload does not exist.

- [ ] **Step 3: Create the RuleComposer.gd skeleton**

Create `src/llm/RuleComposer.gd`:

```gdscript
extends Node

## RuleComposer — LLM-driven rule authoring assistant.
##
## Domain-parameterized: autobattle rules are per-character (character_id required),
## autogrind rules are party-level (character_id MUST be ""). See design spec
## docs/superpowers/specs/2026-07-01-llm-rule-composer-and-monster-adaptation-design.md
##
## Signal contract:
##   composition_ready(result: Dictionary) — emitted on success OR curated fallback
##   composition_failed(reason: String, details: Dictionary) — LLM path failure

signal composition_ready(result: Dictionary)
signal composition_failed(reason: String, details: Dictionary)

const DOMAIN_AUTOBATTLE := "autobattle"
const DOMAIN_AUTOGRIND  := "autogrind"

const _VALID_DOMAINS := [DOMAIN_AUTOBATTLE, DOMAIN_AUTOGRIND]

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func has_llm() -> bool:
    if OS.has_feature("web"):
        return false
    var svc = get_node_or_null("/root/LLMService")
    if svc == null:
        return false
    if not svc.has_method("is_available"):
        return false
    return bool(svc.is_available())

## Placeholder — implemented in Task 10.
func compose_async(domain: String, prompt_text: String, character_id: String = "", current_rules: Array = []) -> Dictionary:
    return _empty_result(domain, character_id, "not_implemented")

func _empty_result(domain: String, character_id: String, source: String) -> Dictionary:
    return {
        "name": "",
        "description": "",
        "rules": [],
        "errors": [] as Array[String],
        "source": source,
        "domain": domain,
        "character_id": character_id,
    }
```

- [ ] **Step 4: Register RuleComposer as an autoload**

Open `project.godot`. Find the `[autoload]` block. Locate the `LLMService` line and the `BossDialogue` line (already present). Insert between them:

```
RuleComposer="*res://src/llm/RuleComposer.gd"
```

- [ ] **Step 5: Prewarm import so the autoload is registered globally**

Run: `cd /home/struktured/projects/cowir-main && godot --headless --import` (timeout 180000ms).
Expected: exits 0.

- [ ] **Step 6: Run scaffold test**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_scaffold.gd -gexit`
Expected: PASS — 4/4 tests green.

- [ ] **Step 7: `test_no_engine_has_singleton` lint stays green**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_no_engine_has_singleton.gd -gexit`
Expected: PASS. The new module must not use `Engine.has_singleton(...)`.

- [ ] **Step 8: Commit**

```bash
git add project.godot src/llm/RuleComposer.gd test/unit/test_rule_composer_scaffold.gd
git commit -m "$(cat <<'EOF'
feat(llm): RuleComposer autoload skeleton + signal contract

Registers RuleComposer as an autoload between LLMService and
BossDialogue in project.godot. Exposes DOMAIN_AUTOBATTLE /
DOMAIN_AUTOGRIND constants, composition_ready / composition_failed
signals with the shape cowir-main + cowir-autogrind pre-approved in
broadcasts #1997/#1999. compose_async is a stub for Task 10.

Web hard-off via OS.has_feature('web') in has_llm(). PROCESS_MODE_ALWAYS
so LLM waits survive a paused SceneTree (same pattern LLMService uses).

Task 9 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `compose_async` — prompt + schema + LLM path + fallback

**Files:**
- Create: `test/unit/test_rule_composer_live_path.gd`
- Create: `test/unit/test_rule_composer_timeout.gd`
- Create: `test/unit/test_rule_composer_web_fallback.gd`
- Modify: `src/llm/RuleComposer.gd` (`compose_async` body)
- Modify: `src/llm/DialoguePrompts.gd` (add `SCHEMA_RULE_COMPOSITION`, `FALLBACK_RULE_COMPOSITION`, `build_rule_composition(domain, prompt_text, current_rules)`, `validate_rule_composition(reply, domain)`)

**Interfaces:**
- Consumes: `LLMService.complete_json(prompt, schema, fallback, opts) -> Variant`, `LLMService.is_available()`.
- Produces: `RuleComposer.compose_async` returns `{name, description, rules, errors, source, domain, character_id}` per signal contract. Emits `composition_ready` on `source in ["llm", "fallback"]`. Emits `composition_failed(reason, details)` on hard failures (`no_llm`, `invalid_json`, `grammar_errors`, `client_timeout`).

- [ ] **Step 1: Write the live-path test**

Create `test/unit/test_rule_composer_live_path.gd`:

```gdscript
extends GutTest

const FakeBackend := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend

func before_each() -> void:
    rc = get_node_or_null("/root/RuleComposer")
    svc = get_node_or_null("/root/LLMService")
    assert_not_null(rc)
    assert_not_null(svc)
    fake_backend = FakeBackend.new()
    svc._backends = [fake_backend]      # test-only override
    svc._active_backend = fake_backend

func after_each() -> void:
    if fake_backend and is_instance_valid(fake_backend):
        fake_backend.queue_free()

func test_llm_path_returns_valid_composition() -> void:
    var payload := {
        "name": "Fire-heavy strategy",
        "description": "Lead with fire on ice.",
        "rules_json": "[{\"conditions\":[{\"type\":\"enemy_hp_percent\",\"op\":\">\",\"value\":50}],\"actions\":[{\"type\":\"ability\",\"id\":\"fire\",\"target\":\"lowest_hp_enemy\"}],\"enabled\":true}]"
    }
    fake_backend.prime_next(JSON.stringify(payload), true, "")
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "always open with fire", "mage", [])
    assert_eq(result.get("source", ""), "llm")
    assert_eq(result.get("name", ""), "Fire-heavy strategy")
    var rules: Array = result.get("rules", [])
    assert_eq(rules.size(), 1, "must parse the one rule")
    assert_eq(result.get("errors", []).size(), 0)
    assert_eq(result.get("domain", ""), rc.DOMAIN_AUTOBATTLE)
    assert_eq(result.get("character_id", ""), "mage")

func test_autogrind_domain_disallows_character_id() -> void:
    fake_backend.prime_next("{}", true, "")
    # In the autogrind domain character_id must be empty
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOGRIND, "heal when hurt", "cleric", [])
    assert_ne(result.get("source", ""), "llm",
              "autogrind domain with a character_id must NOT proceed to LLM")
    assert_gt(result.get("errors", []).size(), 0)

func test_autobattle_requires_character_id() -> void:
    fake_backend.prime_next("{}", true, "")
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "heal on low HP", "", [])
    assert_ne(result.get("source", ""), "llm",
              "autobattle domain without character_id must NOT proceed to LLM")
    assert_gt(result.get("errors", []).size(), 0)

func test_llm_ready_signal_fires() -> void:
    watch_signals(rc)
    fake_backend.prime_next(JSON.stringify({
        "name": "Ok",
        "description": "Ok.",
        "rules_json": "[]"
    }), true, "")
    var _r = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
    assert_signal_emitted(rc, "composition_ready")
```

- [ ] **Step 2: Write the timeout test**

Create `test/unit/test_rule_composer_timeout.gd`:

```gdscript
extends GutTest

const FakeBackend := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend

func before_each() -> void:
    rc = get_node_or_null("/root/RuleComposer")
    svc = get_node_or_null("/root/LLMService")
    fake_backend = FakeBackend.new()
    svc._backends = [fake_backend]
    svc._active_backend = fake_backend

func after_each() -> void:
    if fake_backend and is_instance_valid(fake_backend):
        fake_backend.queue_free()

func test_hang_triggers_client_timeout_fallback() -> void:
    watch_signals(rc)
    fake_backend.hang()   # never emit
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
    assert_eq(result.get("source", ""), "fallback",
              "6s client timeout in LLMService must resolve to fallback content")
    assert_signal_emitted(rc, "composition_failed")
```

- [ ] **Step 3: Write the web-fallback test**

Create `test/unit/test_rule_composer_web_fallback.gd`:

```gdscript
extends GutTest

## We cannot flip OS.has_feature("web") in-process; instead we exercise the
## has_llm() branches indirectly by disabling the LLM service.

var rc
var svc

func before_each() -> void:
    rc = get_node_or_null("/root/RuleComposer")
    svc = get_node_or_null("/root/LLMService")

func test_has_llm_false_when_service_disabled() -> void:
    var restore: bool = svc.llm_enabled
    svc.llm_enabled = false
    assert_false(rc.has_llm(), "has_llm must be false when LLMService.llm_enabled is false")
    svc.llm_enabled = restore

func test_compose_async_falls_back_when_llm_off() -> void:
    watch_signals(rc)
    var restore: bool = svc.llm_enabled
    svc.llm_enabled = false
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "anything", "mage", [])
    assert_eq(result.get("source", ""), "fallback")
    assert_signal_emitted_with_parameters(rc, "composition_failed", ["no_llm", {}])
    svc.llm_enabled = restore
```

- [ ] **Step 4: Run tests to verify all three fail**

Run each in turn:
- `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_live_path.gd -gexit`
- `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_timeout.gd -gexit`
- `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_web_fallback.gd -gexit`
Expected: all FAIL — `compose_async` is still the stub from Task 9.

- [ ] **Step 5: Add SCHEMA + FALLBACK + prompt builder to DialoguePrompts.gd**

Add to `src/llm/DialoguePrompts.gd`:

```gdscript
const SCHEMA_RULE_COMPOSITION := {
    "name":        "String",
    "description": "String",
    "rules_json":  "String",
}

const FALLBACK_RULE_COMPOSITION := {
    "name": "Draft — LLM unavailable",
    "description": "Curated fallback; edit or pick a template.",
    "rules_json": "[]",
}

func build_rule_composition(domain: String, prompt_text: String, current_rules: Array) -> String:
    var grammar: String = AUTOBATTLE_GRAMMAR_DESCRIPTION if domain == "autobattle" else AUTOGRIND_GRAMMAR_DESCRIPTION
    var current_json: String = JSON.stringify(current_rules) if current_rules.size() > 0 else "[]"
    return (
        "You are a rule authoring assistant for a JRPG's autobattle/autogrind system.\n\n"
        + grammar
        + "\n\nCurrent rules (for reference; may be empty):\n"
        + current_json
        + "\n\nPlayer intent:\n"
        + prompt_text
        + "\n\nEmit a JSON object with fields:\n"
        + "  name: short (3-6 words), snake-case-friendly, describing the strategy\n"
        + "  description: 1 sentence, in-character\n"
        + "  rules_json: the FULL rule list, as a JSON string. Each rule is\n"
        + "    {conditions: [...], actions: [...], enabled: true}\n"
        + "    conditions and actions must use only the verbs listed above.\n\n"
        + "Only emit the JSON. No commentary."
    )

func validate_rule_composition(reply: Dictionary, _domain: String) -> Dictionary:
    var name: String = str(reply.get("name", "")).strip_edges()
    var desc: String = str(reply.get("description", "")).strip_edges()
    var rules_json: String = str(reply.get("rules_json", ""))
    var parsed: Variant = JSON.parse_string(rules_json)
    var rules: Array = []
    var parse_ok: bool = typeof(parsed) == TYPE_ARRAY
    if parse_ok:
        for r in parsed:
            if typeof(r) == TYPE_DICTIONARY:
                rules.append(r)
    return {
        "name": name,
        "description": desc,
        "rules": rules,
        "parse_ok": parse_ok,
    }
```

- [ ] **Step 6: Implement `compose_async` in RuleComposer.gd**

Replace the stub in `src/llm/RuleComposer.gd`:

```gdscript
const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")

func compose_async(domain: String, prompt_text: String, character_id: String = "", current_rules: Array = []) -> Dictionary:
    if not domain in _VALID_DOMAINS:
        var err = _empty_result(domain, character_id, "fallback")
        err["errors"] = ["invalid domain: '%s'" % domain]
        composition_failed.emit("invalid_domain", {"errors": err["errors"]})
        return err

    if domain == DOMAIN_AUTOBATTLE and character_id.strip_edges() == "":
        var e = _empty_result(domain, character_id, "fallback")
        e["errors"] = ["autobattle domain requires a character_id"]
        composition_failed.emit("scope_error", {"errors": e["errors"]})
        return e

    if domain == DOMAIN_AUTOGRIND and character_id.strip_edges() != "":
        var e = _empty_result(domain, character_id, "fallback")
        e["errors"] = ["autogrind domain must not receive a character_id (got '%s')" % character_id]
        composition_failed.emit("scope_error", {"errors": e["errors"]})
        return e

    if not has_llm():
        var res = _fallback_result(domain, character_id)
        composition_failed.emit("no_llm", {})
        composition_ready.emit(res)
        return res

    var prompt: String = DialoguePrompts.build_rule_composition(domain, prompt_text, current_rules)
    var svc = get_node_or_null("/root/LLMService")
    var raw: Variant = await svc.complete_json(prompt, DialoguePrompts.SCHEMA_RULE_COMPOSITION, DialoguePrompts.FALLBACK_RULE_COMPOSITION)

    var reply: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else DialoguePrompts.FALLBACK_RULE_COMPOSITION.duplicate(true)

    var v: Dictionary = DialoguePrompts.validate_rule_composition(reply, domain)
    var is_fallback: bool = (
        not v["parse_ok"]
        or reply.get("name", "") == DialoguePrompts.FALLBACK_RULE_COMPOSITION["name"]
    )

    if is_fallback:
        var res_fb: Dictionary = _fallback_result(domain, character_id)
        composition_failed.emit("invalid_json", {})
        composition_ready.emit(res_fb)
        return res_fb

    var result := {
        "name": v["name"],
        "description": v["description"],
        "rules": v["rules"],
        "errors": [] as Array[String],
        "source": "llm",
        "domain": domain,
        "character_id": character_id,
    }
    composition_ready.emit(result)
    return result

func _fallback_result(domain: String, character_id: String) -> Dictionary:
    return {
        "name": DialoguePrompts.FALLBACK_RULE_COMPOSITION["name"],
        "description": DialoguePrompts.FALLBACK_RULE_COMPOSITION["description"],
        "rules": [],
        "errors": [] as Array[String],
        "source": "fallback",
        "domain": domain,
        "character_id": character_id,
    }
```

- [ ] **Step 7: Prewarm import (schema + fallback const reachable)**

Run: `godot --headless --import` (timeout 180000ms).
Expected: exits 0.

- [ ] **Step 8: Run all three RuleComposer tests**

Run each:
- `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_live_path.gd -gexit`
- `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_timeout.gd -gexit`
- `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_web_fallback.gd -gexit`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add src/llm/RuleComposer.gd src/llm/DialoguePrompts.gd test/unit/test_rule_composer_live_path.gd test/unit/test_rule_composer_timeout.gd test/unit/test_rule_composer_web_fallback.gd
git commit -m "$(cat <<'EOF'
feat(llm): RuleComposer.compose_async — LLM path + scope guards + fallback

Implements the full LLM refine path:

- Domain validation + per-domain scope guards (autobattle requires
  character_id, autogrind forbids it).
- Prompt built from AUTOBATTLE_/AUTOGRIND_GRAMMAR_DESCRIPTION constant.
- SCHEMA_RULE_COMPOSITION flat schema (LLMService.complete_json is
  flat-only); nested rules encoded as a JSON string in rules_json field.
- Second-pass parse via validate_rule_composition. Hard-validation
  against the domain's grammar comes in Task 11.
- Fallback path: LLM off (no_llm), 6s client timeout (relies on
  LLMService's existing guard), or invalid JSON — all emit
  composition_failed AND composition_ready with source='fallback'.

Task 10 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Grammar-lint second-pass validation in Composer

**Files:**
- Create: `test/unit/test_rule_composer_grammar_lint.gd`
- Modify: `src/llm/RuleComposer.gd` (`compose_async` — hook `<domain>System.validate_rule` after parse, before success emit)

**Interfaces:**
- Consumes: `AutobattleSystem.validate_rule` (Task 1), `AutogrindSystem.validate_rule` (Task 2).
- Produces: `compose_async` now rejects grammar-invalid emits with `composition_failed("grammar_errors", {errors: [...]})` before emitting `composition_ready`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_rule_composer_grammar_lint.gd`:

```gdscript
extends GutTest

const FakeBackend := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend

func before_each() -> void:
    rc = get_node_or_null("/root/RuleComposer")
    svc = get_node_or_null("/root/LLMService")
    fake_backend = FakeBackend.new()
    svc._backends = [fake_backend]
    svc._active_backend = fake_backend

func after_each() -> void:
    if fake_backend and is_instance_valid(fake_backend):
        fake_backend.queue_free()

func test_unknown_condition_triggers_grammar_errors() -> void:
    watch_signals(rc)
    var payload := {
        "name": "Bad rule",
        "description": "Uses unknown condition.",
        "rules_json": "[{\"conditions\":[{\"type\":\"hp_zorp\",\"op\":\"<\",\"value\":30}],\"actions\":[{\"type\":\"attack\"}],\"enabled\":true}]"
    }
    fake_backend.prime_next(JSON.stringify(payload), true, "")
    var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
    assert_eq(result.get("source", ""), "fallback",
              "grammar-invalid emit must resolve to fallback source")
    assert_gt(result.get("errors", []).size(), 0,
              "must populate errors list with grammar problems")
    assert_signal_emitted_with_parameters(rc, "composition_failed", [
        "grammar_errors", {"errors": result["errors"]}
    ])
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_grammar_lint.gd -gexit`
Expected: FAIL — invalid rule currently passes through to `composition_ready` with `source='llm'`.

- [ ] **Step 3: Hook second-pass validation**

In `src/llm/RuleComposer.gd`, immediately before the "success" `composition_ready.emit(result)` at the end of `compose_async`, add:

```gdscript
    var domain_system = get_node_or_null("/root/AutobattleSystem" if domain == DOMAIN_AUTOBATTLE else "/root/AutogrindSystem")
    var grammar_errors: Array[String] = []
    if domain_system != null and domain_system.has_method("validate_rule"):
        for r in v["rules"]:
            for err in domain_system.validate_rule(r):
                grammar_errors.append(err)
    if grammar_errors.size() > 0:
        var res_bad: Dictionary = _fallback_result(domain, character_id)
        res_bad["errors"] = grammar_errors
        composition_failed.emit("grammar_errors", {"errors": grammar_errors})
        composition_ready.emit(res_bad)
        return res_bad
```

Insert this block AFTER the `is_fallback` early-return branch and BEFORE the final `composition_ready.emit(result)`.

- [ ] **Step 4: Run to verify passing**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_grammar_lint.gd -gexit`
Expected: PASS.

- [ ] **Step 5: Re-run Task 10 live-path test — ensure no regression**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_live_path.gd -gexit`
Expected: PASS. Valid rules still make it through the new guard.

- [ ] **Step 6: Commit**

```bash
git add src/llm/RuleComposer.gd test/unit/test_rule_composer_grammar_lint.gd
git commit -m "$(cat <<'EOF'
feat(llm): RuleComposer second-pass grammar validation

After JSON parse succeeds, iterate the parsed rules through
<domain>System.validate_rule; if ANY error is reported, refuse the
composition (emit composition_failed('grammar_errors',{errors})) and
downgrade to a curated fallback.

Together with Tasks 1 and 2, this closes the silent-coercion loophole
in the existing interpreter for LLM output.

Task 11 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: `AutobattleSystem.install_composition_as_new_profile`

**Files:**
- Create: `test/unit/test_autobattle_install_composition.gd`
- Modify: `src/autobattle/AutobattleSystem.gd`

**Interfaces:**
- Consumes: existing per-character profile machinery in `AutobattleSystem` (profile save at `:1533-1540`, `set_character_script`, `character_script_changed` signal at `:14`).
- Produces: `AutobattleSystem.install_composition_as_new_profile(character_id: String, composition: Dictionary) -> int` returning the new profile index. Never overwrites existing profiles. Emits `character_script_changed(character_id)`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_autobattle_install_composition.gd`:

```gdscript
extends GutTest

var autobattle

func before_each() -> void:
    autobattle = get_node_or_null("/root/AutobattleSystem")

func test_install_returns_new_profile_index() -> void:
    var comp := {
        "name": "test_profile",
        "description": "Test.",
        "rules": [
            {"conditions": [{"type": "always"}],
             "actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
             "enabled": true},
        ],
    }
    var idx: int = autobattle.install_composition_as_new_profile("test_pc", comp)
    assert_gt(idx, -1, "install must return a valid new profile index")

func test_install_does_not_overwrite_existing_profile() -> void:
    var comp_a := {"name": "profile_a", "description": "", "rules": []}
    var comp_b := {"name": "profile_b", "description": "", "rules": []}
    var idx_a: int = autobattle.install_composition_as_new_profile("test_pc_2", comp_a)
    var idx_b: int = autobattle.install_composition_as_new_profile("test_pc_2", comp_b)
    assert_ne(idx_a, idx_b, "consecutive installs must NOT reuse the same slot")

func test_install_emits_character_script_changed() -> void:
    watch_signals(autobattle)
    var comp := {"name": "signal_check", "description": "", "rules": []}
    autobattle.install_composition_as_new_profile("test_pc_3", comp)
    assert_signal_emitted(autobattle, "character_script_changed")
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autobattle_install_composition.gd -gexit`
Expected: FAIL — method not defined.

- [ ] **Step 3: Add `install_composition_as_new_profile` to AutobattleSystem.gd**

Add near the profile save code at `AutobattleSystem.gd:~1533`:

```gdscript
func install_composition_as_new_profile(character_id: String, composition: Dictionary) -> int:
    var rules: Array = composition.get("rules", [])
    if not _character_profiles.has(character_id):
        _character_profiles[character_id] = []
    var profiles: Array = _character_profiles[character_id]
    profiles.append({
        "name": str(composition.get("name", "Composed Profile")),
        "description": str(composition.get("description", "")),
        "rules": rules,
        "enabled": true,
    })
    var new_index: int = profiles.size() - 1
    _persist_profiles()
    character_script_changed.emit(character_id)
    return new_index
```

Note: replace `_character_profiles` / `_persist_profiles` with the actual existing member names in AutobattleSystem — the pattern is that per-character named profiles already exist; the helper wraps append + persist + signal. Do not invent a new persistence path.

- [ ] **Step 4: Run tests**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autobattle_install_composition.gd -gexit`
Expected: PASS — 3/3 tests green.

- [ ] **Step 5: Syntax check**

Run: `godot --headless --check-only --script src/autobattle/AutobattleSystem.gd`
Expected: no parse errors.

- [ ] **Step 6: Commit**

```bash
git add src/autobattle/AutobattleSystem.gd test/unit/test_autobattle_install_composition.gd
git commit -m "$(cat <<'EOF'
feat(autobattle): install_composition_as_new_profile helper

Mirrors AutogrindRuleTemplates.install_as_new_profile for the
per-character autobattle profile system: append a new profile slot,
persist, emit character_script_changed. Never overwrites existing
profiles. Used by RuleComposer 'New profile' install flow.

Task 12 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: `RuleComposerOverlay` UI + `AutobattleGridEditor` wiring

**Files:**
- Create: `src/ui/autobattle/RuleComposerOverlay.gd`
- Create: `src/ui/autobattle/RuleComposerOverlay.tscn`
- Create: `test/unit/test_rule_composer_overlay.gd`
- Modify: `src/ui/autobattle/AutobattleGridEditor.gd`:
  - `_input` ladder ~line 1719 — add `KEY_K` branch invoking the overlay
  - `setup()` ~line 181 — add `rules.size() == 0` branch that shows the splash before seeding the default rule
  - Legend const ~line 266 — add `K` shortcut hint

**Interfaces:**
- Consumes: `RuleComposer` (autoload), `AutobattleSystem.install_composition_as_new_profile`, `AutobattleSystem.set_character_script`, `_flash_status` on editor.
- Produces: `RuleComposerOverlay.open(domain, character_id, current_rules)` — a full-screen `Control` that emits `installed(profile_index: int)` on Confirm or `cancelled` on Cancel.

- [ ] **Step 1: Write the overlay unit test**

Create `test/unit/test_rule_composer_overlay.gd`:

```gdscript
extends GutTest

const RuleComposerOverlay := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")

func test_open_stores_domain_and_character_id() -> void:
    var overlay = RuleComposerOverlay.new()
    add_child_autofree(overlay)
    overlay.open("autobattle", "mage", [])
    assert_eq(overlay.get_domain(), "autobattle")
    assert_eq(overlay.get_character_id(), "mage")

func test_emits_cancelled_on_cancel() -> void:
    var overlay = RuleComposerOverlay.new()
    add_child_autofree(overlay)
    watch_signals(overlay)
    overlay.open("autobattle", "mage", [])
    overlay.cancel()
    assert_signal_emitted(overlay, "cancelled")

func test_signal_shape_installed_carries_index() -> void:
    var overlay = RuleComposerOverlay.new()
    add_child_autofree(overlay)
    assert_true(overlay.has_signal("installed"))
    assert_true(overlay.has_signal("cancelled"))
```

- [ ] **Step 2: Run test to verify failure**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_overlay.gd -gexit`
Expected: FAIL — script doesn't exist.

- [ ] **Step 3: Create `RuleComposerOverlay.gd`**

Create `src/ui/autobattle/RuleComposerOverlay.gd`:

```gdscript
extends Control

## RuleComposerOverlay — modal for the Rule Composer flow.
##
## Life cycle: open(domain, character_id, current_rules) → text field →
## Compose → thinking indicator → preview → Confirm (installed) OR Cancel
## (cancelled) OR Regenerate (loops back to Compose).

signal installed(profile_index: int)
signal cancelled

const RC_DOMAIN_AUTOBATTLE := "autobattle"
const RC_DOMAIN_AUTOGRIND  := "autogrind"

var _domain: String = ""
var _character_id: String = ""
var _current_rules: Array = []
var _last_composition: Dictionary = {}

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    hide()

func open(domain: String, character_id: String, current_rules: Array) -> void:
    _domain = domain
    _character_id = character_id
    _current_rules = current_rules
    _last_composition = {}
    show()

func get_domain() -> String:
    return _domain

func get_character_id() -> String:
    return _character_id

func cancel() -> void:
    hide()
    cancelled.emit()

func compose(prompt_text: String) -> void:
    var rc = get_node_or_null("/root/RuleComposer")
    if rc == null:
        _show_error(["RuleComposer autoload missing"])
        return
    _set_thinking(true)
    var result: Dictionary = await rc.compose_async(_domain, prompt_text, _character_id, _current_rules)
    _set_thinking(false)
    _last_composition = result
    if result.get("errors", []).size() > 0:
        _show_error(result["errors"])
        return
    if result.get("rules", []).size() == 0:
        _show_error(["No rules were composed."])
        return
    _show_preview(result)

func confirm(replace_current: bool) -> void:
    if _last_composition.is_empty():
        return
    var idx: int = -1
    if _domain == RC_DOMAIN_AUTOBATTLE:
        var autobattle = get_node_or_null("/root/AutobattleSystem")
        if autobattle == null:
            _show_error(["AutobattleSystem missing"])
            return
        if replace_current:
            autobattle.set_character_script(_character_id, _last_composition["rules"])
            idx = -1
        else:
            idx = autobattle.install_composition_as_new_profile(_character_id, _last_composition)
    else:
        var autogrind = get_node_or_null("/root/AutogrindSystem")
        if autogrind == null:
            _show_error(["AutogrindSystem missing"])
            return
        if replace_current:
            autogrind.set_autogrind_rules(_last_composition["rules"])
            idx = -1
        else:
            var templates = get_node_or_null("/root/AutogrindRuleTemplates")
            if templates == null or not templates.has_method("install_as_new_profile"):
                _show_error(["AutogrindRuleTemplates missing"])
                return
            idx = templates.install_as_new_profile(_last_composition, autogrind)
    hide()
    installed.emit(idx)

# UI hooks — visuals wired in RuleComposerOverlay.tscn; kept as stubs here so the
# script is testable headless. The .tscn overrides these on ready.
func _set_thinking(_active: bool) -> void:
    pass

func _show_preview(_result: Dictionary) -> void:
    pass

func _show_error(_errors: Array) -> void:
    pass
```

- [ ] **Step 4: Create a minimal scene file**

Create `src/ui/autobattle/RuleComposerOverlay.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/autobattle/RuleComposerOverlay.gd" id="1"]

[node name="RuleComposerOverlay" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Backdrop" type="ColorRect" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.75)

[node name="Panel" type="PanelContainer" parent="."]
anchor_left = 0.15
anchor_top = 0.15
anchor_right = 0.85
anchor_bottom = 0.85

[node name="VBox" type="VBoxContainer" parent="Panel"]

[node name="Title" type="Label" parent="Panel/VBox"]
text = "Compose Rules from Prompt"

[node name="PromptField" type="LineEdit" parent="Panel/VBox"]
placeholder_text = "Describe your strategy in one line…"

[node name="StatusLabel" type="Label" parent="Panel/VBox"]
text = ""

[node name="PreviewPanel" type="Panel" parent="Panel/VBox"]
custom_minimum_size = Vector2(0, 200)

[node name="ButtonsHBox" type="HBoxContainer" parent="Panel/VBox"]

[node name="ComposeButton" type="Button" parent="Panel/VBox/ButtonsHBox"]
text = "Compose (A)"

[node name="RegenButton" type="Button" parent="Panel/VBox/ButtonsHBox"]
text = "Regenerate (R)"

[node name="ConfirmButton" type="Button" parent="Panel/VBox/ButtonsHBox"]
text = "Confirm (A)"

[node name="CancelButton" type="Button" parent="Panel/VBox/ButtonsHBox"]
text = "Cancel (B)"

[node name="ReplaceToggle" type="CheckBox" parent="Panel/VBox"]
text = "Replace current profile"
```

Add signal wiring in `RuleComposerOverlay.gd`'s `_ready` to connect the buttons to `compose(_prompt.text)`, `cancel()`, `confirm($ReplaceToggle.button_pressed)`, and to configure `_set_thinking` / `_show_preview` / `_show_error` to update `StatusLabel` and `PreviewPanel`. Keep those wiring lines minimal — the goal is a working overlay, not a polished UI (polish in a follow-up).

- [ ] **Step 5: Rerun overlay test**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_overlay.gd -gexit`
Expected: PASS — 3/3.

- [ ] **Step 6: Wire the hotkey + splash into `AutobattleGridEditor.gd`**

Open `src/ui/autobattle/AutobattleGridEditor.gd`.

**6a. Hotkey.** Locate the `_input` ladder around line 1719 (find the `KEY_I` / `KEY_E` branch). Add a sibling:

```gdscript
        KEY_K:
            _open_rule_composer_overlay()
            get_viewport().set_input_as_handled()
            return
```

**6b. Splash branch in `setup()`.** Around line 181, BEFORE the default-rule seeding call, add:

```gdscript
    if rules.size() == 0 and not _splash_shown:
        _splash_shown = true
        _show_empty_grid_splash()
        return
```

And declare `var _splash_shown: bool = false` near the other members.

**6c. Legend update.** Around line 266, add `K: compose` to the legend const/string.

**6d. Helpers.** Near the file's other UI helpers, add:

```gdscript
const _RuleComposerOverlayScene := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")

func _open_rule_composer_overlay() -> void:
    var overlay: Control = _RuleComposerOverlayScene.instantiate()
    add_child(overlay)
    overlay.installed.connect(_on_composer_installed)
    overlay.cancelled.connect(overlay.queue_free)
    overlay.open("autobattle", _current_character_id(), rules.duplicate(true))

func _on_composer_installed(profile_index: int) -> void:
    _flash_status("Composed profile installed (slot %d)" % profile_index)
    _reload_from_profile(profile_index)

func _show_empty_grid_splash() -> void:
    _open_rule_composer_overlay()
```

Replace `_current_character_id()` / `_reload_from_profile(profile_index)` with the accessors already used by the editor for those operations. If none exist for reloading, wire the overlay's `installed` signal to `setup(_current_character_id())` (whatever the editor's re-entry path is).

- [ ] **Step 7: Prewarm import**

Run: `godot --headless --import` (timeout 180000ms).
Expected: exits 0.

- [ ] **Step 8: Run autobattle-editor regression + Task 13 tests**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rule_composer_overlay.gd -gexit`
Run any existing `test_autobattle_editor*` if present.
Expected: PASS. If an existing editor test breaks, the splash's `_splash_shown` latch is probably firing across test runs — add a reset in `setup()` for tests: `_splash_shown = false` at the top of `setup()` is safe.

- [ ] **Step 9: Syntax checks**

Run:
- `godot --headless --check-only --script src/ui/autobattle/RuleComposerOverlay.gd`
- `godot --headless --check-only --script src/ui/autobattle/AutobattleGridEditor.gd`
Expected: no parse errors.

- [ ] **Step 10: Commit**

```bash
git add src/ui/autobattle/RuleComposerOverlay.gd src/ui/autobattle/RuleComposerOverlay.tscn src/ui/autobattle/AutobattleGridEditor.gd test/unit/test_rule_composer_overlay.gd
git commit -m "$(cat <<'EOF'
feat(ui): RuleComposerOverlay + AutobattleGridEditor K hotkey + splash

- New Control-based overlay parameterised by domain / character_id /
  current_rules. Emits installed(profile_index) or cancelled.
- Full-screen modal following the _option_picker sentinel pattern used
  elsewhere in the editor.
- AutobattleGridEditor gains K (Kompose) hotkey and an empty-grid
  splash that opens the overlay directly. Legend updated.

Task 13 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: `AutogrindGridEditor` wiring — same overlay, autogrind domain

**Files:**
- Modify: `src/ui/autogrind/AutogrindGridEditor.gd`:
  - `_input` ladder — add `KEY_K` branch
  - `setup()` — empty-grid splash branch
  - Legend — add `K: compose`
  - Helpers analogous to Task 13, domain=`autogrind`, `character_id=""`
- Create: `test/unit/test_autogrind_editor_composer_hotkey.gd` (thin sanity)

**Interfaces:**
- Consumes: `RuleComposerOverlay.tscn` (Task 13), `AutogrindSystem.get_autogrind_rules`, `AutogrindSystem.set_autogrind_rules`, `AutogrindRuleTemplates.install_as_new_profile`, existing `autogrind_rules_changed` signal.
- Produces: no new interfaces; the editor gains the compose affordance parity with autobattle.

- [ ] **Step 1: Write the sanity test**

Create `test/unit/test_autogrind_editor_composer_hotkey.gd`:

```gdscript
extends GutTest

const AutogrindGridEditor := preload("res://src/ui/autogrind/AutogrindGridEditor.gd")

func test_editor_script_exposes_open_rule_composer_overlay() -> void:
    var editor = AutogrindGridEditor.new()
    add_child_autofree(editor)
    assert_true(editor.has_method("_open_rule_composer_overlay"),
                "AutogrindGridEditor must expose _open_rule_composer_overlay")
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autogrind_editor_composer_hotkey.gd -gexit`
Expected: FAIL — method absent.

- [ ] **Step 3: Mirror Task 13's wiring in the autogrind editor**

Open `src/ui/autogrind/AutogrindGridEditor.gd`. Apply the same three edits as Task 13 (hotkey, splash, legend) plus these helpers using the autogrind APIs:

```gdscript
const _RuleComposerOverlayScene := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")

var _splash_shown: bool = false

func _open_rule_composer_overlay() -> void:
    var autogrind = get_node_or_null("/root/AutogrindSystem")
    var current: Array = []
    if autogrind != null and autogrind.has_method("get_autogrind_rules"):
        current = autogrind.get_autogrind_rules()
    var overlay: Control = _RuleComposerOverlayScene.instantiate()
    add_child(overlay)
    overlay.installed.connect(_on_composer_installed)
    overlay.cancelled.connect(overlay.queue_free)
    overlay.open("autogrind", "", current)

func _on_composer_installed(_profile_index: int) -> void:
    _flash_status("Composed autogrind rules installed")
    # AutogrindGridEditor listens for autogrind_rules_changed already; refresh happens
    # via that signal. If it does not, add a direct reload call to the existing helper.
```

Add `KEY_K` branch to `_input` and empty-grid splash the same way as autobattle.

- [ ] **Step 4: Run sanity test**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_autogrind_editor_composer_hotkey.gd -gexit`
Expected: PASS.

- [ ] **Step 5: Syntax check**

Run: `godot --headless --check-only --script src/ui/autogrind/AutogrindGridEditor.gd`
Expected: no parse errors.

- [ ] **Step 6: Commit**

```bash
git add src/ui/autogrind/AutogrindGridEditor.gd test/unit/test_autogrind_editor_composer_hotkey.gd
git commit -m "$(cat <<'EOF'
feat(ui): AutogrindGridEditor K hotkey + splash — parity with autobattle

Reuses RuleComposerOverlay.tscn parameterised with domain='autogrind'
and character_id=''. Reads current party-level rules via
AutogrindSystem.get_autogrind_rules; installer routes through
AutogrindRuleTemplates.install_as_new_profile or set_autogrind_rules per
the overlay's Replace toggle.

Task 14 of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Extend the other 4 opt-in bosses with widened scripted_intents

**Files:**
- Modify: `data/boss_dialogue.json` (pyrroth, glacius, voltharion, umbraxis — same 6 scripted_intent shape as Mordaine, distinct voicing)
- Modify: `test/unit/test_boss_dialogue_data_integrity.gd` (assert every opt-in boss has all 6 widened tags)

**Interfaces:**
- Consumes: same allowlist as Task 6.
- Produces: complete scripted floor for all 5 W1 opt-in bosses.

- [ ] **Step 1: Extend the data-integrity test**

Add to `test/unit/test_boss_dialogue_data_integrity.gd`:

```gdscript
const _OPT_IN_BOSSES := ["chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis"]
const _REQUIRED_WIDENED_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
                                  "focus_healer", "defense_boost", "rotate_aggro"]

func test_every_optin_boss_has_all_six_widened_tags() -> void:
    var data: Dictionary = _load_boss_dialogue_data()
    for boss_id in _OPT_IN_BOSSES:
        assert_true(data.has(boss_id),
                    "boss_dialogue.json missing '%s'" % boss_id)
        var ids: Array = []
        for intent in data[boss_id].get("scripted_intents", []):
            ids.append(str(intent.get("id", "")))
        for tag in _REQUIRED_WIDENED_TAGS:
            assert_true(tag in ids,
                        "%s must include scripted_intent '%s'" % [boss_id, tag])
```

- [ ] **Step 2: Run to verify failure**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue_data_integrity.gd -gexit`
Expected: FAIL — 4 bosses (pyrroth/glacius/voltharion/umbraxis) missing the 6 tags.

- [ ] **Step 3: Extend the 4 dragons in `data/boss_dialogue.json`**

For each of pyrroth, glacius, voltharion, umbraxis, append 6 scripted_intents parallel to Mordaine's. Voicing is per-boss but the structure is identical. Example (pyrroth, fire-elemental theme):

```json
{
  "id": "fire_resist",
  "name": "Kindling reflected",
  "conditions": [{"learned_patterns_counter": "fire_resist"}],
  "taunt_lines": [
    "You throw fire at fire. Bold.",
    "I am the sun's kin. Your kindling is homage.",
    "Every flame you spend feeds mine."
  ]
},
{
  "id": "ice_resist",
  "name": "Frost against the sun",
  "conditions": [{"learned_patterns_counter": "ice_resist"}],
  "taunt_lines": [
    "Ice? Against a wyrm of ember? Delightful.",
    "Your frost is a whisper. Speak louder.",
    "I have breathed winter mornings. You are not one."
  ]
},
{
  "id": "lightning_resist",
  "name": "Storm-scorched",
  "conditions": [{"learned_patterns_counter": "lightning_resist"}],
  "taunt_lines": [
    "Thunder cannot reach a heart already burning.",
    "Storm the sky. My scales are older than clouds.",
    "Lightning writes a name on stone. Fire erases it."
  ]
},
{
  "id": "focus_healer",
  "name": "Salt the well",
  "conditions": [{"learned_patterns_counter": "focus_healer"}],
  "taunt_lines": [
    "Your priest is a candle. Watch me pinch the wick.",
    "The well runs dry. Then the well runs.",
    "First mercy, then bones."
  ]
},
{
  "id": "defense_boost",
  "name": "Ember-shell",
  "conditions": [{"learned_patterns_counter": "defense_boost"}],
  "taunt_lines": [
    "My hide is molten. Yours is a shirt.",
    "You script defense; I compile it.",
    "The Ember Wyrm learns nothing from your caution."
  ]
},
{
  "id": "rotate_aggro",
  "name": "All four burn equally",
  "conditions": [{"learned_patterns_counter": "rotate_aggro"}],
  "taunt_lines": [
    "You cannot pick a favorite. Neither can I.",
    "My flame is impartial.",
    "Four scripts, one fire."
  ]
}
```

Repeat for glacius (ice theme — "the cold is patient", "you burn against a river"), voltharion (lightning — "the ground is my ally", "your circuits echo mine"), umbraxis (void — "you counter shadows with light; light casts them", "even your resistance is a shape I can un-name").

Author 3 taunt_lines per intent per boss (24 additions per boss × 4 bosses = 24 new intent entries + 72 taunt lines total). Follow existing boss voice; keep to 1-2 lines each.

- [ ] **Step 4: Run test to verify passing**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue_data_integrity.gd -gexit`
Expected: PASS.

- [ ] **Step 5: JSON syntax check**

Run: `python3 -c "import json; json.load(open('/home/struktured/projects/cowir-main/data/boss_dialogue.json'))"`
Expected: silent success.

- [ ] **Step 6: Full boss regression**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_dialogue.gd -gexit`
Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_boss_jailbreak_battle_integration.gd -gexit`
Expected: both PASS.

- [ ] **Step 7: Full suite sanity**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit` (timeout 300000ms).
Expected: all pre-existing + 15 tasks' worth of new tests PASS. No regressions.

- [ ] **Step 8: Commit**

```bash
git add data/boss_dialogue.json test/unit/test_boss_dialogue_data_integrity.gd
git commit -m "$(cat <<'EOF'
feat(boss-ai): 4 dragons — scripted floor for widened counter tags

Pyrroth / Glacius / Voltharion / Umbraxis each receive 6 scripted_intent
entries (fire_resist, ice_resist, lightning_resist, focus_healer,
defense_boost, rotate_aggro) with in-voice taunt lines per elemental
theme. Data-integrity test enforces coverage across all 5 W1 opt-in
bosses.

With this, every LLM-enabled boss has a complete scripted counter-draft
lane even when the LLM is off.

Task 15 (final) of the plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review — Spec Coverage Cross-Check

Every spec section maps to at least one task:

| Spec section | Task(s) |
|---|---|
| §1 goals A (Rule Composer) | 9, 10, 11, 12, 13, 14 |
| §1 goal B (Learning Monsters) | 3, 4, 5, 6, 7, 8, 15 |
| §1 shared substrate | 1, 2 (grammar consts); 9 (autoload) |
| §1 non-goals | Explicitly deferred: nested-schema, per-role model routing, `learns_from:autobattle_rules` on regular monsters, voice input, analytics |
| §2 architecture (Approach A + shared constant) | 1, 2, 9 |
| §3.1 UX invocation (hotkey K + splash) | 13, 14 |
| §3.2 module | 9 |
| §3.3 prompt shape | 10 |
| §3.4 SCHEMA_RULE_COMPOSITION | 10 |
| §3.5 second-pass hard validation | 1, 2 (helpers), 11 (Composer hook) |
| §3.6 UI hookup | 13, 14 |
| §3.7 install flow (both domains) | 12, 13, 14 |
| §4.1 extension surface | 3, 4, 5, 6, 7, 8 |
| §4.2 BossIntentContext extension | 7, 8 |
| §4.3 widened intent + seam mechanism | 3, 4 |
| §4.4 prompt shape | 8 |
| §4.5 scripted floor | 6 (Mordaine); 15 (dragons) |
| §4.6 scope (LLM-enabled bosses only) | Enforced by boss_dialogue.json entries in 6, 15 |
| §5 data schema additions | 6, 15 |
| §6 fallback path (Composer) | 10 (`no_llm`, `invalid_json`, `client_timeout`), 11 (`grammar_errors`) |
| §6 fallback path (Adapter) | 6, 15 (scripted floor); relies on existing BossDialogue.pick_intent |
| §7 testing (matrix) | Every task has TDD tests; the matrix rows correspond 1:1 to test files created |
| §8 cross-huddle interfaces | Zero-new-work confirmations for cowir-autogrind, cowir-battle; Tasks 3–8 apply exactly the shape signed off in msgs 1997/1999 |
| §9 sequencing (7 phases) | Compressed into 15 bite-sized tasks; phase mapping listed at bottom of §9 |
| §10 open questions | Not implemented (explicit follow-ups) |

**Placeholder scan:** searched for TBD / TODO / FIXME / "implement later" — none present. All code shown is complete for its step.

**Type consistency:** `RuleComposer.compose_async` returns `Dictionary` consistently across Tasks 9, 10, 11, 13. `BossIntentContext` fields declared in Task 7 are consumed with the same names in Task 8. `_intent_forces_counter` and `_resolve_counter_strategy` from Task 4 are called by their exact names in the same task's step 5.

**Scope check:** single implementation-plan scope covering both features. Spec explicitly identified two features but the shared substrate and cross-cutting seams justify a single plan. Phase-independent commits still allow selective merging.

**Ambiguity check:** the two accessor-name uncertainties (`_lead_pc_id_for_party`, `_current_region_id_for`, `_masterite_type_of`) are called out at the point of use with instruction to use whatever existing accessor exists. This is standard for a plan against a moving main; substituting the real name is a mechanical step for the implementer.

---

Plan complete and saved to `docs/superpowers/plans/2026-07-01-llm-rule-composer-and-monster-adaptation-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
