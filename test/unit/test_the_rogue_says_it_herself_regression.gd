extends GutTest

## Regression: in Scriptura's plaza, a Rogue lead's own line ("There. The small door the whole plaza's walking
## around…", cowir-story msg 2278) was spoken by a separate "villager" NPC on the plaza floor, so the name-hash
## coin flip drew a stranger delivering the Rogue's first-person observation (found by @cowir-sprites, 2026-10-31).
## struktured ruled: no NPC; the Rogue says it herself, once, on the first plaza entry she leads.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SCENE := "world1_scriptura_rogue_door"
const SCENE_PATH := "res://data/cutscenes/world1_scriptura_rogue_door.json"
const PLAZA := "scriptura_plaza"

var _loop: Node
var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}
var _saved_leader: int = 0


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_saved_leader = int(GameState.party_leader_index)
	## A clean slate: no story beat of another map or world may win this entry for an unrelated reason.
	GameState.game_constants = {}
	GameState.party_leader_index = 0
	_loop = load("res://src/GameLoop.gd").new()


func after_each() -> void:
	GameState.game_constants = _saved_constants
	GameState.story_flags = _saved_story
	GameState.party_leader_index = _saved_leader
	if is_instance_valid(_loop):
		_loop.free()


func _led_by(job_id: String) -> void:
	var member := Combatant.new()
	autofree(member)
	member.job = JobSystem.get_job(job_id)
	_loop.party = [member]


func _pending_on(map_id: String) -> String:
	_loop._current_map_id = map_id
	return _loop._get_pending_story_cutscene()


func _scene() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE_PATH))
	return parsed if parsed is Dictionary else {}


func test_a_rogue_lead_hears_it_on_entering_the_plaza() -> void:
	assert_false(JobSystem.get_job("rogue").is_empty(), "CONTROL: the rogue job must exist")
	_led_by("rogue")
	assert_eq(_loop._lead_job_now(), "rogue", "CONTROL: the live roster must read as Rogue-led")
	assert_eq(_pending_on(PLAZA), SCENE, "a Rogue lead entering the plaza must get her line")


func test_any_other_lead_does_not() -> void:
	## CONTROL for the arm above: the gate keys on the lead, so a Fighter-led party walks in silently.
	_led_by("fighter")
	assert_ne(_pending_on(PLAZA), SCENE, "a Fighter lead got the Rogue's line")
	_led_by("rogue")
	assert_ne(_pending_on("harmonia_village"), SCENE, "a Rogue lead got the plaza line on another map")


func test_she_says_it_once() -> void:
	_led_by("rogue")
	var flag: String = str(_loop.get_script().get_script_constant_map()["_CUTSCENE_COMPLETION_FLAGS"].get(SCENE, ""))
	assert_ne(flag, "", "the scene must carry a completion flag or it loops")
	GameState.game_constants[flag] = true
	assert_ne(_pending_on(PLAZA), SCENE, "the line came back after it had been said")


func test_it_never_rides_a_chain() -> void:
	## A beat that finishes on the plaza must not hand the entry straight to this one.
	_led_by("rogue")
	_loop._chaining_story_cutscene = true
	var got: String = _pending_on(PLAZA)
	_loop._chaining_story_cutscene = false
	assert_ne(got, SCENE, "the Rogue's line fired as a chain target")


func test_the_scene_is_the_rogue_speaking() -> void:
	var data: Dictionary = _scene()
	assert_false(data.is_empty(), "the scene must parse")
	var lines: Array = []
	for step in data.get("steps", []):
		if step is Dictionary and str((step as Dictionary).get("type", "")) == "dialogue":
			lines.append_array((step as Dictionary).get("lines", []))
	assert_eq(lines.size(), 1, "one line, said once")
	var line: Dictionary = lines[0]
	assert_eq(str(line.get("speaker", "")), "Rogue", "the line is hers")
	assert_eq(str(line.get("portrait", "")), "rogue", "with her face")
	assert_eq(str(line.get("theme", "")), "rogue", "and her dialogue colours")
	assert_true(str(line.get("text", "")).begins_with("There. The small door the whole plaza's walking around."),
		"the authored line (msg 2278) must survive the move unchanged")


func test_the_scene_closes_the_gate_it_is_gated_on() -> void:
	var flag: String = str(_loop.get_script().get_script_constant_map()["_CUTSCENE_COMPLETION_FLAGS"].get(SCENE, ""))
	var written := ""
	for step in _scene().get("steps", []):
		if step is Dictionary and str((step as Dictionary).get("type", "")) == "set_flag":
			written = "cutscene_flag_" + str((step as Dictionary).get("flag", ""))
	assert_eq(written, flag, "the scene's own set_flag must write the flag the gate reads, or a skipped scene replays")


func test_no_stranger_says_it_any_more() -> void:
	var code: String = GdSource.code_of("res://src/maps/villages/ScripturaPlaza.gd")
	assert_true(code.contains("func _setup_npcs"), "CONTROL: the plaza's code must survive comment-stripping")
	assert_false(code.contains("Four people gave me directions"), "the plaza still places an NPC speaking the Rogue's line")
	assert_true(FileAccess.get_file_as_string(SCENE_PATH).contains("Four people gave me directions"),
		"CONTROL: the line must live in the scene, so its absence above is a move, not a deletion")
