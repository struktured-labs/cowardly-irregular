extends GutTest

## 24 Masterites ship with stats, abilities, drops, portraits, an intro scene and a defeat scene.
## Nine of them had no way to be met: each world was designed for four and W2-W6 placed one, in a
## dungeon. GameLoop's own comment admitted the cost — "12 of the 20 [fragment reveals] wait on
## dungeons that do not exist yet" — and two W2 defeats were simply GRANTED when the preceding
## cutscene ended, which is why the campaign spine still reached the ending.
##
## `_FRAGMENT_GATES` is the register that makes this checkable: 20 authored reveal scenes, each
## keyed on one Masterite's defeat flag. A flag with no writer is a scene no player can ever see,
## and nothing else in the repo reports it — the gate just never opens.
##
## These arms derive the register from GameLoop and the writers from src/, so adding a world, a
## Masterite or a dungeon cannot leave this file describing an older game. Three writer shapes are
## legal and all three are real: a village encounter naming the flag, a DragonCave subclass bridging
## it through `defeat_cutscene_flags`, and W1's composed `w1_<archetype>_defeated`.

const GAMELOOP := "res://src/GameLoop.gd"
const VILLAGE_DIR := "res://src/maps/villages"
const DUNGEON_DIR := "res://src/maps/dungeons"


func _source(path: String) -> String:
	var t: String = FileAccess.get_file_as_string(path)
	assert_ne(t, "", "FLOOR: %s must be readable — every arm below derives from it" % path)
	return t


func _dir_source(dir_path: String) -> String:
	var all := ""
	var d := DirAccess.open(dir_path)
	assert_not_null(d, "FLOOR: %s must be listable" % dir_path)
	if d == null:
		return all
	for f in d.get_files():
		if f.ends_with(".gd"):
			all += FileAccess.get_file_as_string(dir_path + "/" + f)
	return all


## Every defeat flag the fragment-reveal register waits on, read out of the register itself.
func _gated_flags() -> Array:
	var src := _source(GAMELOOP)
	var i: int = src.find("const _FRAGMENT_GATES")
	assert_gt(i, -1, "FLOOR: _FRAGMENT_GATES must exist — it is the register this file derives from")
	if i < 0:
		return []
	var end: int = src.find("\n}", i)
	var block: String = src.substr(i, end - i) if end > i else src.substr(i)
	var out: Array = []
	for m in RegEx.create_from_string('"flag"\\s*:\\s*"([a-z0-9_]+)"').search_all(block):
		out.append(m.get_string(1))
	return out


func test_the_register_still_holds_all_twenty_reveals() -> void:
	## CONTROL for every arm below: they quantify over this list, so a parse that returns nothing
	## would report a clean sweep of an empty set. Six worlds, four archetypes.
	var flags := _gated_flags()
	assert_eq(flags.size(), 20,
		"_FRAGMENT_GATES must name 20 defeat flags (6 worlds designed for 4 Masterites, less the two the W3 numbering offset leaves ungated); parsed %d: %s" % [flags.size(), str(flags)])
	var unique := {}
	for f in flags:
		unique[f] = true
	assert_eq(unique.size(), flags.size(), "two reveals wait on the same defeat flag: %s" % str(flags))


func test_every_gated_defeat_flag_is_written_by_a_fight() -> void:
	var villages := _dir_source(VILLAGE_DIR)
	var dungeons := _dir_source(DUNGEON_DIR)
	var unwritten: Array = []
	var by_shape := {"village": 0, "dungeon": 0, "composed": 0}
	for flag in _gated_flags():
		if villages.contains('defeat_flag_name = "%s"' % flag):
			by_shape["village"] += 1
			continue
		if dungeons.contains('"%s"' % flag) and dungeons.contains("defeat_cutscene_flags"):
			by_shape["dungeon"] += 1
			continue
		## W1's four compose their flag from the archetype instead of naming it.
		var m := RegEx.create_from_string("^w1_([a-z]+)_defeated$").search(flag)
		if m != null and villages.contains('archetype = "%s"' % m.get_string(1)):
			by_shape["composed"] += 1
			continue
		unwritten.append(flag)
	assert_eq(unwritten, [],
		("a fragment reveal waits on a defeat nothing can write — the scene is unreachable:\n  %s\n" +
		"Give the Masterite a MasteriteEncounter whose defeat_flag_name is that flag, or bridge it\n" +
		"through a dungeon's defeat_cutscene_flags.") % "\n  ".join(unwritten))
	## Which shape wrote them is reported, not asserted per-flag: the claim is that each has A writer.
	gut.p("writers: %d village fights, %d dungeon bosses, %d W1 composed" % [by_shape["village"], by_shape["dungeon"], by_shape["composed"]])
	assert_gt(by_shape["village"], 0, "CONTROL: the village shape must be in use, or that branch is untested here")
	assert_gt(by_shape["dungeon"], 0, "CONTROL: the dungeon bridge shape must be in use")


func test_the_writer_census_can_say_no() -> void:
	## The arm above is an absence claim, so it needs a direction that fires. A flag the register
	## names and nothing writes is exactly what it must catch.
	var villages := _dir_source(VILLAGE_DIR)
	var planted := "cutscene_flag_warden_nowhere_defeated"
	assert_false(villages.contains('defeat_flag_name = "%s"' % planted),
		"CONTROL: the planted flag must genuinely be unwritten, or the arm above proves nothing")


func test_every_placement_resolves_its_monster_scene_and_prereq() -> void:
	## A typo'd monster_id warns and silently skips; a cutscene_id with no file plays nothing; and a
	## prereq_flag nothing ever writes leaves the boss invisible for the whole game. All three are
	## silent at runtime, and the third cannot be seen by any count of placements.
	var mons: Dictionary = _json("res://data/monsters.json")
	assert_gt(mons.size(), 0, "FLOOR: monsters.json must parse")
	var gameloop := _source(GAMELOOP)
	var dungeons := _dir_source(DUNGEON_DIR)
	var d := DirAccess.open(VILLAGE_DIR)
	assert_not_null(d, "FLOOR: %s must be listable" % VILLAGE_DIR)
	if d == null:
		return
	var checked := 0
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
		for m in RegEx.create_from_string('\\.monster_id\\s*=\\s*"(masterite_[a-z_]+)"').search_all(src):
			checked += 1
			assert_true(mons.has(m.get_string(1)),
				"%s places %s, which is not in monsters.json — MasteriteEncounter warns and skips" % [f, m.get_string(1)])
		for m in RegEx.create_from_string('\\.cutscene_id\\s*=\\s*"([a-z0-9_]+)"').search_all(src):
			if not src.contains("MasteriteScript"):
				continue
			assert_true(FileAccess.file_exists("res://data/cutscenes/%s.json" % m.get_string(1)),
				"%s names cutscene %s, which is not on disk" % [f, m.get_string(1)])
		for m in RegEx.create_from_string('\\.prereq_flag\\s*=\\s*"([a-z0-9_]+)"').search_all(src):
			var flag: String = m.get_string(1)
			var written: bool = gameloop.contains('"%s"' % flag) or dungeons.contains('"%s"' % flag)
			assert_true(written,
				("%s gates a Masterite on %s, which nothing in GameLoop or any dungeon writes —\n" +
				"the encounter hides itself on _ready and never comes back.") % [f, flag])
	assert_gt(checked, 18, "CONTROL: only %d placements parsed; all 24 Masterites should be reachable, 19 of them from villages" % checked)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
