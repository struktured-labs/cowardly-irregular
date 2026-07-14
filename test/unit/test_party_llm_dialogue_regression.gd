extends GutTest

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")
const PartyCombatLineContextScript := preload("res://src/battle/PartyCombatLineContext.gd")


# ── PartyCombatLineContext ────────────────────────────────────────────────────

func test_context_push_recent_caps_at_limit() -> void:
	var ctx = PartyCombatLineContextScript.new()
	for i in range(PartyCombatLineContextScript.RECENT_LIMIT + 4):
		ctx.push_recent({"actor": "p%d" % i, "ability_id": "attack"})
	assert_eq(ctx.recent_actions.size(), PartyCombatLineContextScript.RECENT_LIMIT,
		"recent_actions must hard-cap at RECENT_LIMIT")
	var newest: Dictionary = ctx.recent_actions[ctx.recent_actions.size() - 1]
	assert_eq(newest.get("actor", ""), "p%d" % (PartyCombatLineContextScript.RECENT_LIMIT + 3),
		"newest push must remain after eviction")


func test_context_to_dict_shape() -> void:
	var ctx = PartyCombatLineContextScript.new()
	ctx.event_kind = "turn_start"
	ctx.speaker_name = "Hero"
	ctx.speaker_job_id = "fighter"
	var d: Dictionary = ctx.to_dict()
	for key in ["event_kind", "speaker_name", "speaker_job_id", "speaker_personality",
				"speaker_hp_pct", "speaker_mp_pct", "speaker_ap", "speaker_status",
				"party", "enemies", "recent_actions", "event_data"]:
		assert_true(d.has(key), "to_dict must include key '%s'" % key)


func test_known_event_constants_match_battle_manager() -> void:
	for ev in ["turn_start", "low_hp", "big_hit_taken", "used_signature_ability", "victory"]:
		var matched: bool = (
			ev == PartyCombatLineContextScript.EVENT_TURN_START
			or ev == PartyCombatLineContextScript.EVENT_LOW_HP
			or ev == PartyCombatLineContextScript.EVENT_BIG_HIT_TAKEN
			or ev == PartyCombatLineContextScript.EVENT_USED_SIGNATURE_ABILITY
			or ev == PartyCombatLineContextScript.EVENT_VICTORY
		)
		assert_true(matched, "event id '%s' must be present in PartyCombatLineContext constants" % ev)


# ── SCHEMA + FALLBACK ─────────────────────────────────────────────────────────

func test_schema_party_line_keys() -> void:
	var sch: Dictionary = DialoguePrompts.SCHEMA_PARTY_LINE
	for key in ["line", "mood"]:
		assert_true(sch.has(key), "SCHEMA_PARTY_LINE must declare '%s'" % key)


func test_fallback_party_line_signals_empty_line() -> void:
	var fb: Dictionary = DialoguePrompts.FALLBACK_PARTY_LINE
	assert_eq(str(fb.get("line", "x")), "",
		"FALLBACK_PARTY_LINE.line must be empty so caller routes to the scripted pool")


# ── build_party_line prompt structure ────────────────────────────────────────

func test_prompt_includes_persona_and_event_hint() -> void:
	var ctx_dict: Dictionary = {
		"event_kind": "turn_start",
		"speaker_name": "Vex",
		"speaker_job_id": "rogue",
		"speaker_personality": "QUICK",
		"speaker_hp_pct": 80.0,
		"speaker_mp_pct": 60.0,
		"speaker_status": [],
		"party": [{"name": "Hero", "job_id": "fighter", "hp_pct": 90, "is_alive": true}],
		"enemies": [{"name": "Slime", "hp_pct": 100}],
		"recent_actions": [],
		"event_data": {},
	}
	var prompt: String = DialoguePrompts.build_party_line(
		"You are Vex the rogue, a daggers operative.",
		["Heist rules.", "You're broadcasting."],
		ctx_dict,
	)
	assert_true(prompt.find("Vex") != -1, "prompt must include speaker name")
	assert_true(prompt.find("rogue") != -1, "prompt must include speaker job_id")
	assert_true(prompt.find("Vex the rogue") != -1, "prompt must include persona text")
	assert_true(prompt.find("Heist rules.") != -1, "prompt must list a signature phrase")
	for key in ["line", "mood"]:
		assert_true(prompt.find("\"%s\"" % key) != -1,
			"prompt must instruct the LLM to include '%s' in JSON output" % key)


func test_prompt_event_hints_differ() -> void:
	var hint_keys: Array = ["turn_start", "low_hp", "big_hit_taken", "used_signature_ability", "victory"]
	var hints: Dictionary = {}
	for ek in hint_keys:
		var ctx_dict: Dictionary = {
			"event_kind": ek, "speaker_name": "Hero", "speaker_job_id": "fighter",
			"party": [], "enemies": [], "recent_actions": [], "event_data": {},
		}
		hints[ek] = DialoguePrompts.build_party_line("PERSONA", [], ctx_dict)
	for a in hint_keys:
		for b in hint_keys:
			if a == b:
				continue
			assert_ne(hints[a], hints[b],
				"event '%s' prompt must differ from event '%s' (per-event hint distinguishes them)" % [a, b])


# ── validate_party_line ──────────────────────────────────────────────────────

func test_validate_rejects_non_dictionary() -> void:
	var got: Dictionary = DialoguePrompts.validate_party_line("not a dict")
	assert_eq(got.get("line", "?"), "", "non-Dict raw must fall back to empty-line envelope")


func test_validate_rejects_empty_line() -> void:
	var got: Dictionary = DialoguePrompts.validate_party_line({"line": "", "mood": "focused"})
	assert_eq(got.get("line", "?"), "", "empty line must fall back")


func test_validate_clamps_long_line() -> void:
	var long_line: String = "a".repeat(DialoguePrompts.MAX_PARTY_LINE_CHARS + 50)
	var got: Dictionary = DialoguePrompts.validate_party_line({"line": long_line, "mood": "focused"})
	assert_true(str(got.get("line", "")).length() <= DialoguePrompts.MAX_PARTY_LINE_CHARS,
		"line must be clamped to MAX_PARTY_LINE_CHARS")


func test_validate_unknown_mood_falls_to_neutral() -> void:
	var got: Dictionary = DialoguePrompts.validate_party_line({"line": "hi", "mood": "gleefully_unhinged"})
	assert_eq(str(got.get("mood", "")), "neutral",
		"unknown mood must coerce to 'neutral' (whitelist)")


func test_validate_accepts_valid() -> void:
	var got: Dictionary = DialoguePrompts.validate_party_line({"line": "Steel speaks plain.", "mood": "focused"})
	assert_eq(str(got.get("line", "")), "Steel speaks plain.",
		"valid line must round-trip")
	assert_eq(str(got.get("mood", "")), "focused",
		"valid mood must round-trip")


# ── GameState flag default ───────────────────────────────────────────────────

func test_party_llm_dialogue_flag_defaults_off() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState autoload unavailable")
		return
	assert_true("party_llm_dialogue_enabled" in gs,
		"GameState must expose party_llm_dialogue_enabled")
	if not gs.party_llm_dialogue_enabled:
		assert_false(gs.party_llm_dialogue_enabled,
			"party_llm_dialogue_enabled must default to false (opt-in)")


# ── PartyPersonas autoload sanity ────────────────────────────────────────────

func test_party_personas_loads_all_starter_jobs() -> void:
	var pp: Node = get_node_or_null("/root/PartyPersonas")
	if pp == null:
		pending("PartyPersonas autoload unavailable")
		return
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		assert_true(pp.has_persona(job),
			"PartyPersonas must have entry for '%s'" % job)
		var persona: String = str(pp.get_persona(job))
		assert_gt(persona.length(), 200,
			"%s persona must be substantive (>200 chars), got %d" % [job, persona.length()])


func test_party_personas_trigger_voices_present_for_each_event() -> void:
	var pp: Node = get_node_or_null("/root/PartyPersonas")
	if pp == null:
		pending("PartyPersonas autoload unavailable")
		return
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		for ev in ["turn_start", "low_hp", "big_hit_taken", "used_signature_ability", "victory"]:
			var line: String = str(pp.get_trigger_voice(job, ev))
			assert_gt(line.length(), 0,
				"%s.trigger_voices.%s must be authored (LLM-off fallback)" % [job, ev])


# ── BattleManager gating ─────────────────────────────────────────────────────

func test_maybe_fire_party_line_no_op_when_flag_off() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	var gs: Node = get_node_or_null("/root/GameState")
	if bm == null or gs == null:
		pending("autoloads unavailable")
		return
	if not bm.has_method("_maybe_fire_party_line"):
		pending("hook missing — Phase C not landed?")
		return
	var prior: bool = gs.party_llm_dialogue_enabled
	gs.party_llm_dialogue_enabled = false
	# Build a fixture combatant inside the player_party temporarily.
	var c: Combatant = Combatant.new()
	c.combatant_name = "FixturePC"
	c.max_hp = 100; c.current_hp = 100
	c.is_alive = true
	add_child_autofree(c)
	## Tick 182: typed-array trap fix — Array[Combatant] field
	## with generic [c] literal silently SCRIPT ERROR'd and
	## aborted the test before the assert.
	var snapshot: Array[Combatant] = bm.player_party.duplicate()
	var typed_party: Array[Combatant] = [c]
	bm.player_party = typed_party
	# With flag OFF, calling the hook is a silent no-op — no exception, no log.
	bm._maybe_fire_party_line(c, "turn_start", {})
	# Restore.
	bm.player_party = snapshot
	gs.party_llm_dialogue_enabled = prior
	assert_true(true, "hook must not crash when called with flag off (sanity)")


func test_cooldown_dictionary_clears_on_battle_start() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable")
		return
	if not ("_party_line_cooldowns" in bm):
		pending("_party_line_cooldowns missing — Phase C not landed?")
		return
	bm._party_line_cooldowns = {"Hero": 4, "Mira": 7}
	# Drive start_battle with empty parties — it should reset the cooldowns.
	bm.start_battle([] as Array[Combatant], [] as Array[Combatant])
	assert_eq(bm._party_line_cooldowns.size(), 0,
		"_party_line_cooldowns must be cleared by start_battle")
