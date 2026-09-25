extends GutTest

## struktured 2026-09-24: "I really like the voice acting, can we add WAY more lines". Each party
## trigger held ONE scripted line, so a character said the same thing every time. A trigger_voices
## entry may now be a list. Variant n speaks clip voice_<job>_<trigger>_<n>; variant 0 keeps the
## unsuffixed clip, so every existing string entry and its clip are unchanged.

var _saved_rogue: Dictionary
var _saved_last: Dictionary
var _saved_llm: bool
var _saved_party: Array
var _saved_round: int


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()
	_saved_llm = GameState.party_llm_dialogue_enabled
	_saved_party = BattleManager.player_party.duplicate()
	_saved_round = BattleManager.current_round


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue
	PartyPersonas._last_variant = _saved_last
	GameState.party_llm_dialogue_enabled = _saved_llm
	BattleManager.player_party.assign(_saved_party.filter(func(c): return is_instance_valid(c)))
	BattleManager.current_round = _saved_round
	BattleManager._party_line_cooldowns.clear()
	BattleManager._party_line_last_kind.clear()


func _rogue_says(lines: Variant) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func test_a_single_string_keeps_its_unsuffixed_clip() -> void:
	_rogue_says("Only line.")
	var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "turn_start")
	assert_eq(p.get("line"), "Only line.")
	assert_eq(p.get("voice_key"), "turn_start", "a one-line trigger must still play voice_rogue_turn_start")


func test_variant_n_names_its_own_clip() -> void:
	_rogue_says(["zero", "one", "two"])
	PartyPersonas._last_variant["rogue|turn_start"] = 0
	var seen := {}
	for i in 60:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "turn_start")
		seen[p["voice_key"]] = p["line"]
	assert_eq(seen.get("turn_start_1"), "one", "variant 1 must play voice_rogue_turn_start_1, the clip cut from its own line")
	assert_eq(seen.get("turn_start_2"), "two")
	assert_eq(seen.get("turn_start"), "zero", "variant 0 keeps the unsuffixed clip")
	assert_eq(seen.size(), 3, "every variant must be reachable, saw %s" % [seen.keys()])


func test_a_variant_is_never_said_twice_running() -> void:
	_rogue_says(["a", "b", "c"])
	var last := ""
	var repeats := 0
	for i in 200:
		var line: String = PartyPersonas.pick_trigger_voice("rogue", "turn_start")["line"]
		if line == last:
			repeats += 1
		last = line
	assert_eq(repeats, 0, "the same line played back to back %d times in 200 picks" % repeats)


func test_the_old_accessor_reads_variant_zero() -> void:
	_rogue_says(["first", "second"])
	assert_eq(PartyPersonas.get_trigger_voice("rogue", "turn_start"), "first",
		"callers of get_trigger_voice must get a line, not a stringified list")
	assert_eq(PartyPersonas.get_trigger_lines("rogue", "turn_start"), ["first", "second"])


func test_the_battle_line_carries_the_variant_clip() -> void:
	_rogue_says(["zero", "one"])
	PartyPersonas._last_variant["rogue|turn_start"] = 0   # two variants, no repeat -> variant 1
	GameState.party_llm_dialogue_enabled = false
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "VariantRogue"
	c.job = {"id": "rogue"}
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	var heard: Array = []
	var cb := func(_who, line, trigger): heard.append([line, trigger])
	BattleManager.party_combat_line.connect(cb)
	BattleManager._run_party_line_async(c, "turn_start", {})
	BattleManager.party_combat_line.disconnect(cb)
	assert_eq(heard.size(), 1, "the scripted line must be emitted")
	if heard.size() == 1:
		assert_eq(heard[0], ["one", "turn_start_1"],
			"the bubble read variant 1 but the clip key named variant 0's recording")


func test_every_authored_entry_is_a_line_or_a_list_of_lines() -> void:
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_personas.json"))
	assert_true(root is Dictionary, "job_personas parses")
	var jobs: Dictionary = (root as Dictionary).get("jobs", {})
	var checked := 0
	for job_id in jobs:
		var tv: Dictionary = jobs[job_id].get("trigger_voices", {})
		for trig in tv:
			checked += 1
			var e: Variant = tv[trig]
			if e is Array:
				assert_gt((e as Array).size(), 0, "%s.%s is an empty list" % [job_id, trig])
				for l in e:
					assert_true(_is_line(l), "%s.%s holds a non-line: %s" % [job_id, trig, l])
			else:
				assert_true(e is String and str(e) != "", "%s.%s must be a line or a list of lines" % [job_id, trig])
	assert_gte(checked, 25, "the scan found the trigger entries at all")


## A line is a non-empty string, or {"line", "when"} with a non-empty line; which tags are legal is test_every_voice_line_tag_is_one_the_picker_knows's job.
func _is_line(l: Variant) -> bool:
	if l is String:
		return str(l) != ""
	if not (l is Dictionary):
		return false
	for k in (l as Dictionary).keys():
		if not (k in ["line", "when"]):
			return false
	return (l as Dictionary).get("line") is String and VoiceLines.text_of(l) != ""
