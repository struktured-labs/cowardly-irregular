extends GutTest

## Regression: presentation_tier(time_scale, turbo, autogrind) DERIVES time_scale from
## Engine when omitted but ASSERTS false for the two bools. A no-arg call therefore claims
## "not turbo, not grinding" on the caller's behalf, in the unsafe direction, returning a
## valid Tier with no error. Every motion gate that read it animated through a visible
## autogrind and through turbo.
##
## This recurred: the class was fixed once, then b3050df7 (UI motion — menu arrival,
## breathing cursor, CTB pulse) landed three NEW no-arg gates because nothing failed when
## it did. The ratchet below is the part that makes the fix stick.
##
## Fix: consumers call BattleJuice.battle_tier(), which reads turbo/autogrind off the
## registered burst_host (BattleScene.gd sets it to self).

const SRC_ROOT := "res://src"


func _gd_files(root: String, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := root + "/" + name
		if dir.current_is_dir():
			if not name.begins_with("."):
				_gd_files(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()


## Code lines only — a doc comment naming presentation_tier() is not a call site.
func _blind_call_sites() -> Array:
	var files: Array = []
	_gd_files(SRC_ROOT, files)
	var hits: Array = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var lineno := 0
		for line in text.split("\n"):
			lineno += 1
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.contains("presentation_tier()"):
				hits.append(path + ":" + str(lineno))
	return hits


# The scan must be able to SEE the corpus before its zero means anything.
func test_scanner_reaches_the_source_tree() -> void:
	var files: Array = []
	_gd_files(SRC_ROOT, files)
	assert_gt(files.size(), 100,
		"scanner found %d .gd files under res://src — too few to be a real sweep" % files.size())
	assert_true(files.has("res://src/battle/BattleJuice.gd"),
		"scanner must reach BattleJuice.gd, which declares the function under test")


# Control: the scanner's predicate fires on a string that IS present.
func test_scanner_predicate_finds_a_known_present_call() -> void:
	var text := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(text.contains("BattleJuice.battle_tier()"),
		"BattleScene._tier() must delegate to battle_tier() — if this fails the ratchet below is vacuous")


# THE RATCHET. A new no-arg gate fails here rather than shipping blind.
func test_no_consumer_reads_presentation_tier_with_no_arguments() -> void:
	var hits := _blind_call_sites()
	assert_eq(hits.size(), 0,
		"presentation_tier() called with NO ARGUMENTS asserts 'not turbo, not autogrind' " +
		"for the caller and animates through both. Call BattleJuice.battle_tier() instead. Sites: " +
		str(hits))


## Node.set() does NOT create a property, so `"turbo_mode" in node` stays false on a bare
## Node — the stub needs a real script for battle_tier()'s `in` checks to see the context.
func _host(turbo: bool, autogrind: bool) -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar turbo_mode := false\nvar autogrind_console_mode := false\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.turbo_mode = turbo
	n.autogrind_console_mode = autogrind
	autofree(n)
	return n


# Behavioural: the two functions must DISAGREE under autogrind, or the conversion bought nothing.
func test_battle_tier_suppresses_under_autogrind_where_presentation_tier_does_not() -> void:
	var host := _host(false, true)

	var prev = BattleJuice.burst_host
	BattleJuice.burst_host = host
	var engine_prev := Engine.time_scale
	Engine.time_scale = 0.25

	var blind := BattleJuice.presentation_tier()
	var aware := BattleJuice.battle_tier()

	Engine.time_scale = engine_prev
	BattleJuice.burst_host = prev

	assert_eq(aware, BattleJuice.Tier.OFF,
		"battle_tier() must resolve OFF while autogrind_console_mode is set on burst_host")
	assert_ne(blind, BattleJuice.Tier.OFF,
		"presentation_tier() with no args must NOT see autogrind — this is the defect being guarded")


# Turbo is the sibling mode and takes the same path.
func test_battle_tier_suppresses_under_turbo() -> void:
	var host := _host(true, false)

	var prev = BattleJuice.burst_host
	BattleJuice.burst_host = host
	var engine_prev := Engine.time_scale
	Engine.time_scale = 0.25

	var aware := BattleJuice.battle_tier()

	Engine.time_scale = engine_prev
	BattleJuice.burst_host = prev

	assert_eq(aware, BattleJuice.Tier.OFF,
		"battle_tier() must resolve OFF while turbo_mode is set on burst_host")
