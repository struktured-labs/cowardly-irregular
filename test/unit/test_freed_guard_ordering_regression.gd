extends GutTest

## `and` short-circuits left to right, and `x is T` on a freed instance ABORTS the enclosing
## function. So `x is T and is_instance_valid(x)` is a guard that can NEVER run its own
## validity check — present, correct, and unreachable. Order matters; presence does not.
## Found by cowir-cutscenes in CutsceneDirector; 7 instances existed in src/battle.
## The reorder is semantically identical for valid and null operands and only removes the
## abort, so unlike the param-typing variant of this class it costs nothing to hold at zero.

const BATTLE_DIR := "res://src/battle"


func _bad_ordering(source: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_.]*)\\s+is\\s+[A-Za-z_][A-Za-z0-9_]*")
	for line in source.split("\n"):
		for m in re.search_all(line):
			var operand: String = m.get_string(1)
			var iv: int = line.find("is_instance_valid(" + operand + ")")
			if iv != -1 and iv > m.get_start():
				out.append(line.strip_edges())
	return out


func _gd_files(dir_path: String) -> Array:
	var found: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return found
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			found.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			found.append(full)
		name = d.get_next()
	return found


func test_detector_fires_on_the_bad_order() -> void:
	## ARM+: a zero below means nothing without this.
	var bad := "\tif s is AnimatedSprite2D and is_instance_valid(s):\n"
	assert_eq(_bad_ordering(bad).size(), 1, "ARM+: detector flags `is` before is_instance_valid")


func test_detector_accepts_the_good_order() -> void:
	## ARM-: the fixed form must not be reported, or the assert below can never pass.
	var good := "\tif is_instance_valid(s) and s is AnimatedSprite2D:\n"
	assert_eq(_bad_ordering(good).size(), 0, "ARM-: validity first is the correct order")


func test_battle_lane_has_no_dead_ordering_guards() -> void:
	var files := _gd_files(BATTLE_DIR)
	assert_gt(files.size(), 5, "CONTROL: enumerated the battle sources")
	var offenders: Array = []
	for f in files:
		for hit in _bad_ordering(FileAccess.get_file_as_string(f)):
			offenders.append(f.get_file() + ": " + hit)
	assert_eq(offenders.size(), 0, "guards whose `is` runs before their validity check: " + str(offenders))


func test_a_freed_sprite_does_not_abort_hitstop_mid_list() -> void:
	## Behavioural arm. It must observe an effect that only occurs if hitstop COMPLETES:
	## the `is` abort kills hitstop itself, not this test, so "did I survive the call" is
	## vacuous and passes with the bug present. The freed sprite goes FIRST so a bad guard
	## aborts before the live one is ever reached.
	var doomed := AnimatedSprite2D.new()
	add_child(doomed)
	doomed.free()
	var alive := AnimatedSprite2D.new()
	add_child_autofree(alive)
	alive.speed_scale = 1.0
	BattleJuice.hitstop([doomed, alive], 0.01)
	assert_eq(alive.speed_scale, 0.0,
		"the live sprite BEHIND the freed one was frozen — a bad guard aborts hitstop before reaching it")
