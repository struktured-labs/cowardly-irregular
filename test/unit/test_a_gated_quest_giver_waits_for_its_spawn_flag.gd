extends GutTest

## giver.spawn_flag has no src reader; each gated giver's map repeats it as a literal, so assert the two AGREE at runtime.

const QUESTS := "res://data/quests"

## npc_id -> the map script that places it, built for real.
const GIVERS := {
	"madame_orrery_w1": "res://src/exploration/OverworldScene.gd",
	"casper_kid": "res://src/maps/villages/MapleHeightsVillage.gd",
}

## A live quest whose spawn_flag is honoured some other way. The reason is the deliverable, not a skip.
const OTHER_GATES := {
	"warden_tally_wall": "a wall prop, always present; the quest's prereq_flag is the same flag and gates the offer",
}

var _saved_flags: Dictionary = {}
var _saved_consts: Dictionary = {}


func before_each() -> void:
	_saved_flags = GameState.story_flags.duplicate(true)
	_saved_consts = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.story_flags = _saved_flags.duplicate(true)
	GameState.game_constants = _saved_consts.duplicate(true)


## Every live (not wiring_pending) quest whose giver authors a spawn_flag: [quest_id, npc_id, flag].
func _gated() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(QUESTS):
		if not f.ends_with(".json"):
			continue
		var q: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUESTS + "/" + f))
		if not (q is Dictionary) or bool((q as Dictionary).get("wiring_pending", false)):
			continue
		var g: Dictionary = (q as Dictionary).get("giver", {})
		var flag := str(g.get("spawn_flag", ""))
		if flag != "":
			out.append([str(q.get("id", f)), str(g.get("npc_id", "")), flag])
	return out


func _clear(flag: String) -> void:
	GameState.story_flags.erase(flag)
	GameState.game_constants.erase(flag)
	GameState.game_constants.erase("cutscene_flag_" + flag)


func _has_npc(n: Node, npc_id: String) -> bool:
	if "npc_id" in n and str(n.get("npc_id")) == npc_id:
		return true
	for c in n.get_children():
		if _has_npc(c, npc_id):
			return true
	return false


func _built_has(path: String, npc_id: String) -> bool:
	var scene: Node = (load(path) as GDScript).new()
	add_child_autofree(scene)
	await get_tree().process_frame
	return _has_npc(scene, npc_id)


func test_the_gated_giver_roster_is_derived_not_assumed() -> void:
	var gated := _gated()
	assert_gt(gated.size(), 1, "FLOOR: the quest corpus has live spawn-gated givers to judge")
	var seen := {}
	for row in gated:
		seen[row[1]] = true
		assert_true(GIVERS.has(row[1]) or OTHER_GATES.has(row[1]),
			"%s's giver %s is gated on '%s' in its JSON, and no map here is checked for honouring it" % row)
	for id in GIVERS.keys() + OTHER_GATES.keys():
		assert_true(seen.has(id), "%s is listed here but no live quest gates it any more" % id)
	for id in OTHER_GATES:
		assert_gt(str(OTHER_GATES[id]).length(), 20, "%s needs the reason its gate is honoured elsewhere" % id)


func test_a_gated_giver_appears_only_once_the_flag_its_quest_names_is_set() -> void:
	var checked := 0
	for row in _gated():
		var npc_id: String = row[1]
		if not GIVERS.has(npc_id):
			continue
		var flag: String = row[2]
		_clear(flag)
		assert_false(await _built_has(GIVERS[npc_id], npc_id), "CONTROL: %s stands on its map with '%s' unset" % [npc_id, flag])
		GameState.set_story_flag(flag, true)
		assert_true(await _built_has(GIVERS[npc_id], npc_id), "%s is missing with '%s' set, the flag %s's JSON names" % [npc_id, flag, row[0]])
		_clear(flag)
		checked += 1
	assert_eq(checked, GIVERS.size(), "every listed giver was built both ways")
