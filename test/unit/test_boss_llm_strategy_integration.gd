extends GutTest

## Boss strategic-intent LLM hook — integration test for the
## BattleManager._update_boss_dialogue_phase wiring landed in Phase 1.
##
## What we drive directly:
##   • Build a Mordaine combatant fixture (no scene tree, no battle loop)
##   • Set boss_dialogue_phase meta = 0 so the next call counts as a
##     transition
##   • Drop HP below the 66% gate so new_phase becomes 2
##   • Call BattleManager._update_boss_dialogue_phase
##   • Assert combatant.get_meta("llm_intent") is set to one of Mordaine's
##     phase-2-eligible intents (aggress / turtle — exploit_pattern is
##     also phase-2-eligible, all three are valid post-call)
##
## What we DON'T drive (intentional):
##   • Actual LLM network call. With Ollama running this would round-trip,
##     but the suite must work without Ollama. The deterministic baseline
##     is what we assert on; the LLM refinement is fire-and-forget and
##     only OVERRIDES the meta later if the call succeeds. Tested
##     separately in test_boss_llm_strategy_regression.gd.

const MORDAINE_ID := "chancellor_mordaine"


func _make_mordaine() -> Combatant:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var m: Dictionary = data[MORDAINE_ID]
	var c: Combatant = Combatant.new()
	c.combatant_name = m["name"]
	c.max_hp = m["stats"]["max_hp"]
	c.current_hp = c.max_hp
	c.max_mp = m["stats"]["max_mp"]
	c.current_mp = c.max_mp
	c.attack = m["stats"]["attack"]
	c.defense = m["stats"]["defense"]
	c.magic = m["stats"]["magic"]
	c.speed = m["stats"]["speed"]
	c.is_alive = true
	c.set_meta("monster_type", MORDAINE_ID)
	add_child_autofree(c)
	return c


func _phase_two_eligible_intents() -> Array[String]:
	# Reads data/boss_dialogue.json to pre-filter the intent pool for
	# phase 2 — anything with min_phase ≤ 2 (or no min_phase).
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_dialogue.json"))
	var ids: Array[String] = []
	var entry: Dictionary = data.get(MORDAINE_ID, {})
	for it in entry.get("scripted_intents", []):
		if not (it is Dictionary):
			continue
		var min_phase: int = int(it.get("conditions", {}).get("min_phase", 1))
		if min_phase <= 2:
			ids.append(str(it.get("id", "")))
	return ids


func test_phase_transition_sets_llm_intent_meta() -> void:
	# Drive the wiring at the BattleManager autoload level.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable in GUT runtime")
		return

	var boss := _make_mordaine()
	# Bring Mordaine to 55% HP so the gate trips into phase 2 (66% threshold).
	boss.current_hp = int(boss.max_hp * 0.55)
	# Mark the boss as "last in phase 1" so the next call is a transition.
	boss.set_meta("boss_dialogue_phase", 1)
	# Pre-condition: no llm_intent yet.
	boss.set_meta("llm_intent", "")

	bm._update_boss_dialogue_phase(boss)

	# Either the deterministic pick set it, or the LLM fired and refined.
	# In a no-LLM CI environment, the deterministic value lands synchronously.
	var got: String = str(boss.get_meta("llm_intent", ""))
	var eligible := _phase_two_eligible_intents()
	assert_true(got in eligible,
		"After phase transition, llm_intent meta must be one of the phase-eligible IDs (%s). Got '%s'." % [str(eligible), got])
	# Phase meta must have advanced past 1.
	assert_eq(int(boss.get_meta("boss_dialogue_phase", 0)), 2,
		"boss_dialogue_phase meta must advance to 2 after the transition")


func test_no_transition_below_phase_threshold_leaves_intent_alone() -> void:
	# At 80% HP we're still in phase 1 — _update_boss_dialogue_phase
	# should be a no-op when new_phase <= last_phase.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable in GUT runtime")
		return

	var boss := _make_mordaine()
	boss.current_hp = int(boss.max_hp * 0.8)
	boss.set_meta("boss_dialogue_phase", 1)
	boss.set_meta("llm_intent", "preset_marker_value")

	bm._update_boss_dialogue_phase(boss)

	assert_eq(str(boss.get_meta("llm_intent", "")), "preset_marker_value",
		"_update_boss_dialogue_phase must NOT clobber llm_intent when no phase boundary is crossed")
	assert_eq(int(boss.get_meta("boss_dialogue_phase", 0)), 1,
		"boss_dialogue_phase meta must remain at 1 when no transition fires")


func test_build_intent_context_captures_party_and_boss_state() -> void:
	# Drives the snapshot builder directly with a small party + boss.
	# Verifies the context surfaces every field the prompt will use.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable in GUT runtime")
		return
	if not bm.has_method("_build_boss_intent_context"):
		pending("_build_boss_intent_context missing — Phase 1 not landed?")
		return

	# Stand up a fixture party with two members, one wounded.
	bm.player_party.clear()
	var p1: Combatant = Combatant.new()
	p1.combatant_name = "Hero"
	p1.max_hp = 100; p1.current_hp = 80
	p1.max_mp = 30; p1.current_mp = 20
	p1.is_alive = true
	add_child_autofree(p1)
	bm.player_party.append(p1)

	var p2: Combatant = Combatant.new()
	p2.combatant_name = "Mira"
	p2.max_hp = 80; p2.current_hp = 0  # KO'd
	p2.max_mp = 50; p2.current_mp = 50
	p2.is_alive = false
	add_child_autofree(p2)
	bm.player_party.append(p2)

	var boss := _make_mordaine()
	boss.current_hp = int(boss.max_hp * 0.4)  # Phase 3 territory.

	var boss_dlg: Node = get_node_or_null("/root/BossDialogue")
	if boss_dlg == null:
		pending("BossDialogue autoload unavailable")
		return

	var ctx: BossIntentContext = bm._build_boss_intent_context(boss, MORDAINE_ID, 3, boss_dlg)
	assert_not_null(ctx, "_build_boss_intent_context must return a BossIntentContext")
	assert_eq(ctx.boss_id, MORDAINE_ID, "boss_id must round-trip into the context")
	assert_eq(ctx.phase, 3, "phase must round-trip")
	# HP-pct math: Combatant.get_hp_percentage returns 0..100.
	assert_almost_eq(ctx.boss_hp_pct, 40.0, 0.5,
		"boss_hp_pct should reflect the live current_hp/max_hp ratio (40 +/- 0.5)")
	# Party should be 2 entries — alive AND dead are both included so the
	# LLM knows the dead slot can be revived.
	assert_eq(ctx.party.size(), 2, "context.party must include EVERY slot, alive or dead")
	# Find the KO entry.
	var ko_seen: bool = false
	for member in ctx.party:
		if not bool(member.get("is_alive", true)):
			ko_seen = true
			break
	assert_true(ko_seen, "the KO'd party member must be present with is_alive=false")
	# Available intents — phase 3, so EVERY scripted intent is eligible.
	assert_gt(ctx.available_intents.size(), 0,
		"available_intents must be populated for a boss with scripted_intents in JSON")
	# Persona must come from data/boss_dialogue.json's chancellor_mordaine entry
	# (the persona block was authored when scripted_intents were).
	# An empty persona means the data file regressed.
	# Note: BossDialogue might not have a "persona" key directly; the
	# builder falls back to a display-name blurb. Either path produces a
	# non-empty string.
	assert_gt(ctx.persona.length(), 0,
		"persona must be a non-empty string (data persona OR display-name fallback)")

	# Clean up.
	bm.player_party.clear()
