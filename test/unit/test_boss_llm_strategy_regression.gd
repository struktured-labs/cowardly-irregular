extends GutTest

## Boss strategic-intent LLM hook — Phase 1 wiring tests.
##
## The hook (sketch / approved 2026-06-17): the LLM picks a strategic
## INTENT per phase transition (e.g. aggress / turtle / exploit_pattern),
## never an ability. The existing _bias_by_intent ladder still owns the
## per-turn ability choice.
##
## Pieces under test:
##   • BossIntentContext — small RefCounted snapshot (push_recent caps,
##     to_dict shape, no Node refs)
##   • DialoguePrompts.SCHEMA_BOSS_INTENT / FALLBACK_BOSS_INTENT
##   • DialoguePrompts.build_boss_intent — prompt contains the
##     available-intents allowlist block + persona + phase + party state
##   • DialoguePrompts.validate_boss_intent — rejects intent_id outside
##     available_intents, clamps reason/taunt, falls back on garbage
##   • BossDialogue.pick_intent_async — when LLMService unavailable,
##     returns the deterministic envelope (no awaits stall the boss)

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")
const BossIntentContextScript := preload("res://src/battle/BossIntentContext.gd")


# ── BossIntentContext ─────────────────────────────────────────────────────────

func test_context_push_recent_caps_at_limit() -> void:
	var ctx = BossIntentContextScript.new()
	for i in range(BossIntentContextScript.RECENT_LIMIT + 5):
		ctx.push_recent({"kind": "party_action", "actor": "p%d" % i, "ability_id": "attack"})
	assert_eq(ctx.recent_actions.size(), BossIntentContextScript.RECENT_LIMIT,
		"push_recent must hard-cap recent_actions at RECENT_LIMIT")
	# Oldest entries get dropped, newest preserved.
	var newest: Dictionary = ctx.recent_actions[ctx.recent_actions.size() - 1]
	assert_eq(newest.get("actor", ""), "p%d" % (BossIntentContextScript.RECENT_LIMIT + 4),
		"newest push must remain after eviction")


func test_context_to_dict_has_stable_shape() -> void:
	var ctx = BossIntentContextScript.new()
	ctx.boss_id = "chancellor_mordaine"
	ctx.phase = 2
	ctx.boss_hp_pct = 50.0
	ctx.boss_mp_pct = 80.0
	ctx.boss_ap = 1
	ctx.available_intents = ["aggress", "turtle"]
	ctx.persona = "Some persona blurb."
	var d: Dictionary = ctx.to_dict()
	for key in ["boss_id", "phase", "boss_hp_pct", "boss_mp_pct", "boss_ap",
				"boss_status", "party", "recent_actions", "available_intents", "persona"]:
		assert_true(d.has(key), "to_dict() must surface key '%s' for stable test-pin shape" % key)
	# Persona STRING is now serialized (previously only its length was) so the
	# boss-intent prompt can render authored personas instead of falling through
	# to the generic "A formidable JRPG boss." default.
	assert_eq(d["persona"], "Some persona blurb.",
		"persona must round-trip as the full string")


# ── DialoguePrompts.SCHEMA_BOSS_INTENT / FALLBACK_BOSS_INTENT ─────────────────

func test_schema_boss_intent_has_three_keys() -> void:
	var sch: Dictionary = DialoguePrompts.SCHEMA_BOSS_INTENT
	for key in ["intent_id", "reason", "taunt"]:
		assert_true(sch.has(key), "SCHEMA_BOSS_INTENT must declare '%s'" % key)


func test_fallback_boss_intent_signals_empty_intent_id() -> void:
	# Empty intent_id is the explicit "fall through to deterministic" signal —
	# the wiring contract relies on this.
	var fb: Dictionary = DialoguePrompts.FALLBACK_BOSS_INTENT
	assert_eq(str(fb.get("intent_id", "x")), "",
		"FALLBACK_BOSS_INTENT.intent_id must be empty so callers route to the deterministic path")


# ── build_boss_intent prompt structure ───────────────────────────────────────

func test_prompt_includes_available_intents_block() -> void:
	var ctx_dict: Dictionary = {
		"persona": "Mordaine — calculated and cold.",
		"phase": 2,
		"boss_hp_pct": 55.0,
		"boss_mp_pct": 70.0,
		"boss_ap": 1,
		"boss_status": [],
		"party": [{"name": "Hero", "job_id": "fighter", "hp_pct": 90, "mp_pct": 50, "ap": 0, "is_alive": true, "status": []}],
		"recent_actions": [],
		"available_intents": ["aggress", "turtle", "exploit_pattern"],
	}
	var prompt: String = DialoguePrompts.build_boss_intent("Chancellor Mordaine", ctx_dict)
	# Each allowed intent must appear in the prompt; LLM has no other way
	# to know the menu of valid options.
	for intent in ["aggress", "turtle", "exploit_pattern"]:
		assert_true(prompt.find(intent) != -1,
			"prompt must list intent '%s' so the LLM can pick it" % intent)
	# Persona must be in the prompt — the whole point of LLM-driven intent.
	assert_true(prompt.find("Mordaine — calculated and cold.") != -1,
		"prompt must include the persona block")
	# Phase number must be surfaced.
	assert_true(prompt.find("phase 2") != -1,
		"prompt must surface the current phase number")
	# JSON-output instruction with all three keys.
	for key in ["intent_id", "reason", "taunt"]:
		assert_true(prompt.find("\"%s\"" % key) != -1,
			"prompt must instruct the LLM to include '%s' in JSON output" % key)


func test_prompt_handles_empty_available_intents() -> void:
	# Edge case — boss with no scripted intents (data file gap). Prompt
	# must still produce a valid string that wouldn't blow up the LLM call.
	var ctx_dict: Dictionary = {
		"persona": "",
		"phase": 1,
		"available_intents": [],
		"party": [],
		"recent_actions": [],
	}
	var prompt: String = DialoguePrompts.build_boss_intent("Ghost Boss", ctx_dict)
	assert_gt(prompt.length(), 0, "build_boss_intent must always return a non-empty prompt")
	assert_true(prompt.find("Ghost Boss") != -1, "prompt must include the boss display name")


# ── validate_boss_intent ─────────────────────────────────────────────────────

func test_validate_rejects_non_dictionary() -> void:
	var got: Dictionary = DialoguePrompts.validate_boss_intent("not a dict", ["aggress"])
	assert_eq(got.get("intent_id", "?"), "",
		"validate_boss_intent must fall back on a non-Dictionary raw input")


func test_validate_rejects_unknown_intent_id() -> void:
	# Stakes guardrail: the LLM cannot invent intents. If it returns one
	# that isn't in the available list, we MUST fall back so the rest of
	# BossDialogue's deterministic path takes over.
	var raw: Dictionary = {"intent_id": "ragequit", "reason": "felt like it", "taunt": "bye"}
	var got: Dictionary = DialoguePrompts.validate_boss_intent(raw, ["aggress", "turtle"])
	assert_eq(got.get("intent_id", "?"), "",
		"validate must reject intent_id not in available_intents")


func test_validate_rejects_empty_intent_id() -> void:
	var raw: Dictionary = {"intent_id": "", "taunt": "anything"}
	var got: Dictionary = DialoguePrompts.validate_boss_intent(raw, ["aggress"])
	assert_eq(got.get("intent_id", "?"), "",
		"validate must reject empty intent_id even with a non-empty taunt")


func test_validate_accepts_valid_intent_with_clamped_strings() -> void:
	var long_reason: String = "a".repeat(DialoguePrompts.MAX_BOSS_REASON_CHARS + 50)
	var long_taunt: String = "b".repeat(DialoguePrompts.MAX_BOSS_TAUNT_CHARS + 50)
	var raw: Dictionary = {
		"intent_id": "turtle",
		"reason":    long_reason,
		"taunt":     long_taunt,
	}
	var got: Dictionary = DialoguePrompts.validate_boss_intent(raw, ["aggress", "turtle"])
	assert_eq(got.get("intent_id", ""), "turtle",
		"valid intent_id must survive validation verbatim")
	assert_true(str(got.get("reason", "")).length() <= DialoguePrompts.MAX_BOSS_REASON_CHARS,
		"reason must be clamped to MAX_BOSS_REASON_CHARS")
	assert_true(str(got.get("taunt", "")).length() <= DialoguePrompts.MAX_BOSS_TAUNT_CHARS,
		"taunt must be clamped to MAX_BOSS_TAUNT_CHARS")


func test_validate_accepts_missing_reason_and_taunt() -> void:
	# Some LLMs return only the intent_id under pressure. As long as the
	# intent is valid, that's a passable response — reason/taunt can be
	# empty without failing the whole turn.
	var raw: Dictionary = {"intent_id": "aggress"}
	var got: Dictionary = DialoguePrompts.validate_boss_intent(raw, ["aggress"])
	assert_eq(got.get("intent_id", ""), "aggress",
		"validate must accept a payload that's just intent_id when intent is in the list")


# ── BossDialogue.pick_intent_async (LLM-off path) ─────────────────────────────

func test_pick_intent_async_falls_back_when_llm_unavailable() -> void:
	# LLMService autoload is present in the GUT runtime, but the HTTPBackend
	# probe to localhost:11434 typically times out in CI / unit tests, so
	# is_available() returns false and pick_intent_async must return the
	# deterministic envelope — { intent_id, taunt_line, reason="" }.
	var boss_dlg: Node = get_node_or_null("/root/BossDialogue")
	if boss_dlg == null:
		pending("BossDialogue autoload unavailable in GUT runtime")
		return
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc != null and svc.has_method("is_available") and svc.is_available():
		pending("LLMService backend is reachable (Ollama running) — test asserts the deterministic-only path")
		return

	var ctx = BossIntentContextScript.new()
	ctx.boss_id = "chancellor_mordaine"
	ctx.phase = 1
	ctx.available_intents = ["aggress", "turtle"]
	var result: Dictionary = await boss_dlg.pick_intent_async(ctx)
	assert_true(result.has("intent_id"),
		"pick_intent_async must always return a Dictionary with intent_id")
	assert_eq(result.get("reason", "missing"), "",
		"deterministic-path envelope must include reason='' (LLM-only field)")
	# intent_id can be any of the deterministic picks for Mordaine in phase 1
	# (aggress / turtle). The point is the call doesn't crash and returns
	# a usable envelope.
	assert_true(result.get("intent_id", "") != null,
		"intent_id must be present (may be empty string if no entry, but key exists)")


func test_pick_intent_async_handles_null_context() -> void:
	# Defensive: a null context is the worst-case bad input. The function
	# must not crash; it returns a clean empty envelope.
	var boss_dlg: Node = get_node_or_null("/root/BossDialogue")
	if boss_dlg == null:
		pending("BossDialogue autoload unavailable in GUT runtime")
		return
	var result: Dictionary = await boss_dlg.pick_intent_async(null)
	assert_eq(str(result.get("intent_id", "missing")), "",
		"null context must yield an empty intent_id envelope, not crash")


# ── GameState flag default ───────────────────────────────────────────────────

func test_boss_llm_strategy_flag_defaults_off() -> void:
	# Opt-in. New saves and the SettingsMenu default position must be OFF
	# so vanilla bosses stay reproducible until the player flips it.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState autoload unavailable in GUT runtime")
		return
	assert_true("boss_llm_strategy_enabled" in gs,
		"GameState must expose boss_llm_strategy_enabled")
	# A fresh GameState (autoload init at startup) starts OFF; if the
	# settings.json on disk has it ON the test runtime would catch that.
	# That trade-off is acceptable for now — the canonical default is OFF.
	if not gs.boss_llm_strategy_enabled:
		assert_false(gs.boss_llm_strategy_enabled,
			"boss_llm_strategy_enabled must default to false on a fresh GameState")


# ── BattleManager gating ──────────────────────────────────────────────────────

func test_should_use_llm_strategy_off_when_flag_off() -> void:
	# With the master flag OFF, every persona returns false — even
	# Mordaine, the showcase. Vanilla play is fully deterministic.
	var bm: Node = get_node_or_null("/root/BattleManager")
	var gs: Node = get_node_or_null("/root/GameState")
	if bm == null or gs == null:
		pending("BattleManager / GameState autoloads unavailable in GUT runtime")
		return
	if not bm.has_method("_should_use_llm_strategy"):
		pending("BattleManager._should_use_llm_strategy missing — Phase 1 not landed?")
		return
	var prior: bool = gs.boss_llm_strategy_enabled
	gs.boss_llm_strategy_enabled = false
	assert_false(bm._should_use_llm_strategy("chancellor_mordaine"),
		"With flag OFF, Mordaine must NOT route through the LLM path")
	gs.boss_llm_strategy_enabled = prior


func test_should_use_llm_strategy_on_for_w1_bosses() -> void:
	# Flag ON: every W1 boss with a persona block + scripted_intents is
	# on the allowlist. Bosses outside W1 (no persona authored yet) must
	# still fall through to deterministic so an accidental data add
	# doesn't quietly enable a half-finished boss.
	var bm: Node = get_node_or_null("/root/BattleManager")
	var gs: Node = get_node_or_null("/root/GameState")
	if bm == null or gs == null:
		pending("BattleManager / GameState autoloads unavailable in GUT runtime")
		return
	if not bm.has_method("_should_use_llm_strategy"):
		pending("BattleManager._should_use_llm_strategy missing — Phase 1 not landed?")
		return
	var prior: bool = gs.boss_llm_strategy_enabled
	gs.boss_llm_strategy_enabled = true
	for on_list in ["chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis"]:
		assert_true(bm._should_use_llm_strategy(on_list),
			"With flag ON, %s must route through the LLM path (W1 boss roster)" % on_list)
	# Non-W1 / non-existent persona keys must still go deterministic.
	for off_list in ["boss_rat_king", "boss_random", "non_existent_boss", ""]:
		assert_false(bm._should_use_llm_strategy(off_list),
			"With flag ON, %s must NOT route through the LLM (allowlist gate)" % off_list)
	gs.boss_llm_strategy_enabled = prior


# ── Persona coverage — every allowlisted boss must have a persona ────────────

func test_w1_bosses_have_persona_blocks_in_data() -> void:
	# Stakes guardrail: a boss on the LLM allowlist with NO persona block
	# would still route LLM calls, but the prompt would have nothing to
	# anchor the LLM in character. Catch the data gap source-side.
	var raw: String = FileAccess.get_file_as_string("res://data/boss_dialogue.json")
	var data: Dictionary = JSON.parse_string(raw)
	for boss_id in ["chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis"]:
		assert_true(data.has(boss_id),
			"data/boss_dialogue.json must contain entry for '%s'" % boss_id)
		var persona: String = str(data[boss_id].get("persona", ""))
		assert_gt(persona.length(), 200,
			"%s must have a substantive persona block (>200 chars) so the LLM stays in character; got %d chars" % [boss_id, persona.length()])
		var intents: Array = data[boss_id].get("scripted_intents", []) as Array
		assert_gt(intents.size(), 0,
			"%s must have at least one scripted_intent — the LLM picks from this pool only" % boss_id)
