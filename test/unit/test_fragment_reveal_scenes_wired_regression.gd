extends GutTest

## All 20 masterite fragment scenes (world*_fragment_*.json) had zero callers — and they carry 20 of
## the game's 21 grant_item key-item reveals, so no fragment was ever granted and the reveal panel
## had one live caller (cowir-adhoc's 72-orphan audit + my count, 2026-09-11). Each scene's
## authored trigger names its masterite by TITLE (arbiter_efficiency_defeated); the engine writes
## world-theme flags (cutscene_flag_arbiter_industrial_defeated). _FRAGMENT_GATES maps each scene
## to the flag its masterite's dungeon writes — derived from the trigger resolved against
## monsters.json (the trigger is the authority, not the filename: world3_fragment_* are the
## INDUSTRIAL set) — and chains it behind that world's aftermath scene once that scene is wired.

var _loop: Node
var _saved: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_clear_flags()
	_loop = load("res://src/GameLoop.gd").new()


func after_each() -> void:
	if is_instance_valid(_loop):
		_loop.free()
	GameState.game_constants = _saved
	GameState.story_flags = _saved_story


func _clear_flags() -> void:
	for k in GameState.game_constants.keys():
		if str(k).begins_with("cutscene_flag_"):
			GameState.game_constants.erase(k)
	GameState.story_flags.clear()


func _pending() -> String:
	_loop._current_map_id = "nowhere_in_particular"
	return _loop._get_pending_story_cutscene()


## Sets a flag the way its writer does: cutscene_flag_* into game_constants (DragonCave), a bare name into story_flags (MasteriteEncounter's w1_<arch>_defeated).
func _flag(k: String) -> void:
	if k.begins_with("cutscene_flag_"):
		GameState.game_constants[k] = true
	else:
		GameState.set_story_flag(k, true)


func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out


## trigger "<arch>_<title>_defeated" → the one masterite_<arch>_<theme> whose name/id contains the title.
func _theme_for_trigger(trigger: String, masterites: Dictionary) -> String:
	var arch := trigger.split("_")[0]
	var title := trigger.substr(arch.length() + 1, trigger.length() - arch.length() - 1 - "_defeated".length())
	var hits: Array[String] = []
	for mid in masterites:
		if not str(mid).begins_with("masterite_" + arch + "_"):
			continue
		if _slug(str(masterites[mid].get("name", ""))).contains(title) or _slug(str(mid)).contains(title):
			hits.append(str(mid))
	assert_eq(hits.size(), 1, "%s must name exactly one masterite, found %s" % [trigger, hits])
	return str(hits[0]).split("_", true, 2)[2] if hits.size() == 1 else ""


func test_the_gate_table_is_the_data_every_fragment_scene_maps_to_its_masterites_flag() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var mons = raw.get("monsters", raw) if raw is Dictionary else raw
	var masterites := {}
	var entries: Array = mons.values() if mons is Dictionary else mons
	for m in entries:
		if m is Dictionary and str(m.get("id", "")).begins_with("masterite_"):
			masterites[m["id"]] = m
	assert_eq(masterites.size(), 24, "control: 24 masterites (6 themes × 4 archetypes)")
	var dir := DirAccess.open("res://data/cutscenes")
	dir.list_dir_begin()
	var f := dir.get_next()
	var seen := 0
	while f != "":
		if f.begins_with("world") and f.contains("_fragment_") and f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
			var cid: String = str(d.get("id", ""))
			seen += 1
			assert_true(_loop._FRAGMENT_GATES.has(cid), "%s has a gate" % cid)
			if _loop._FRAGMENT_GATES.has(cid):
				var theme := _theme_for_trigger(str(d.get("trigger", "")), masterites)
				var arch := str(d.get("trigger", "")).split("_")[0]
				# W1 masterites are village MasteriteEncounters and write "w1_<arch>_defeated" as a STORY flag; every other theme is a DragonCave writing cutscene_flag_<arch>_<theme>_defeated.
				var expected: String = ("w1_%s_defeated" % arch) if theme == "medieval" else ("cutscene_flag_%s_%s_defeated" % [arch, theme])
				assert_eq(str(_loop._FRAGMENT_GATES[cid]["flag"]), expected,
					"%s: the gate flag must be the one its masterite's defeat actually writes" % cid)
			assert_eq(str(_loop._CUTSCENE_COMPLETION_FLAGS.get(cid, "")), "cutscene_flag_%s_complete" % cid, "%s is in the completion map" % cid)
		f = dir.get_next()
	dir.list_dir_end()
	assert_eq(seen, 20, "control: 20 fragment scenes on disk")
	assert_eq(_loop._FRAGMENT_GATES.size(), 20, "and no gate without a scene")


func test_each_fragment_plays_once_its_masterite_falls_and_then_never_again() -> void:
	for fid in _loop._FRAGMENT_GATES:
		_clear_flags()
		var g: Dictionary = _loop._FRAGMENT_GATES[fid]
		assert_eq(_pending(), "", "%s: nothing pending before its masterite falls" % fid)
		_flag(str(g["flag"]))
		var after: String = str(g["after"])
		if _loop._CUTSCENE_COMPLETION_FLAGS.has(after):
			assert_ne(_pending(), fid, "%s: with the aftermath wired, the reveal waits behind it" % fid)
			_flag(str(_loop._CUTSCENE_COMPLETION_FLAGS[after]))
		# The masterite flag also unlocks that world's next chapter (W2 keys chapter3/5/7 on it); those play first and the reveal follows through the chain. Drain the chain as the runtime would.
		var chain: Array[String] = []
		var cur := _pending()
		while cur != fid and cur != "" and chain.size() < 6:
			assert_true(_loop._CUTSCENE_COMPLETION_FLAGS.has(cur), "%s: chained scene %s must be in the completion map" % [fid, cur])
			_flag(str(_loop._CUTSCENE_COMPLETION_FLAGS.get(cur, "cutscene_flag_%s_complete" % cur)))
			chain.append(cur)
			cur = _pending()
		assert_eq(cur, fid, "%s: pending once its masterite falls (after the chain %s)" % [fid, chain])
		_flag("cutscene_flag_%s_complete" % fid)
		assert_ne(_pending(), fid, "%s: never again once complete" % fid)


func test_one_reveal_completing_does_not_block_another() -> void:
	_flag("w1_arbiter_defeated")  # the W1 encounter's story flag — the namespace the gate must read through
	_flag("w1_tempo_defeated")
	var first := _pending()
	assert_true(first in ["world1_fragment_arbiter", "world1_fragment_tempo"], "one of the two is pending: %s" % first)
	_flag("cutscene_flag_%s_complete" % first)
	var second := _pending()
	assert_true(second in ["world1_fragment_arbiter", "world1_fragment_tempo"] and second != first, "then the other: %s" % second)


func test_at_least_the_dungeons_that_exist_today_can_reach_a_reveal() -> void:
	# Control against a vacuous table: the flags gated on must be ones some dungeon actually declares.
	var declared := ""
	var dir := DirAccess.open("res://src/maps/dungeons")
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			declared += FileAccess.get_file_as_string("res://src/maps/dungeons/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	# The W1 masterites are village encounters, not dungeons: MasteriteEncounter composes "w1_%s_defeated" for all four.
	var encounter := FileAccess.get_file_as_string("res://src/exploration/MasteriteEncounter.gd")
	var w1_contract := encounter.contains("\"w1_%s_defeated\" % archetype")
	assert_true(w1_contract, "control: MasteriteEncounter still composes w1_<archetype>_defeated")
	var reachable: Array[String] = []
	for fid in _loop._FRAGMENT_GATES:
		var flag := str(_loop._FRAGMENT_GATES[fid]["flag"])
		if declared.contains("\"%s\"" % flag) or (w1_contract and flag.begins_with("w1_") and flag.ends_with("_defeated")):
			reachable.append(fid)
	assert_gte(reachable.size(), 8, "four W1 encounters + four masterite dungeons exist today, so at least eight reveals are reachable now: %s" % [reachable])
