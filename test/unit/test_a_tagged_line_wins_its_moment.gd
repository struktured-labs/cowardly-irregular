extends GutTest

## Eligible tagged lines outrank generic ones; with no context, tagged lines are never guessed at.

var _saved_rogue: Dictionary = {}
var _saved_last: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue
	PartyPersonas._last_variant = _saved_last


func _rogue_says(lines: Variant) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["low_hp"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func _ctx(party: Array) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Vex"
	c.party = party
	c.enemies = [{"name": "Slime", "hp_pct": 100.0}]
	return c


const LINES := ["Generic one.", "Generic two.", {"line": "Cleric, now.", "when": "ally_alive:cleric"}]


func test_in_a_duel_the_ally_line_never_plays() -> void:
	_rogue_says(LINES)
	var duel := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true}])
	for i in 80:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "low_hp", duel)
		assert_ne(p["line"], "Cleric, now.", "no Cleric in a solo duel, so this line must never play")


func test_when_its_moment_comes_the_tagged_line_wins() -> void:
	_rogue_says(LINES)
	var party := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 90.0, "is_alive": true}])
	var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "low_hp", party)
	assert_eq(p["line"], "Cleric, now.", "an eligible line written for this moment must outrank the generic ones")
	assert_eq(p["voice_key"], "low_hp_2", "and it keeps its own clip, index 2")


func test_without_context_a_tagged_line_is_not_guessed_at() -> void:
	_rogue_says(LINES)
	for i in 60:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "low_hp")
		assert_ne(p["line"], "Cleric, now.", "a caller with no context cannot know the tag holds")


func test_the_eligible_set_is_what_the_llm_chooses_among() -> void:
	_rogue_says(LINES)
	var duel := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true}])
	var e: Array = PartyPersonas.eligible_trigger_entries("rogue", "low_hp", duel)
	var texts: Array = e.map(func(x): return x["line"])
	assert_eq(texts, ["Generic one.", "Generic two."], "the LLM must only ever see lines that are true")
