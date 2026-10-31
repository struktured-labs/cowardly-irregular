extends GutTest

## What a touched roamer fights as was decided SIX times, once per overworld (W1-W6), plus six copies of the two elite
## helpers. They were identical, measured before the fold, and identical is the state a copy drifts out of: the
## elite helpers had already carried a dead autoload lookup in all six at once. The rule now lives in
## MonsterSpawner.group_for_touch, and it is also the seam a chained encounter will grow from.

const ORDINARY := "goblin"
const AUTHORED_ELITE := "dark_knight"
const SAMPLES := 300


func _sources_under(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_sources_under(dir_path.path_join(d), out)
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))


func _body_of(src: String, signature: String) -> String:
	var at: int = src.find(signature)
	if at < 0:
		return ""
	var end: int = src.find("\nfunc ", at + 1)
	return src.substr(at, (end - at) if end > at else -1)


func test_every_overworld_takes_its_group_from_the_one_rule() -> void:
	var files: Array = []
	_sources_under("res://src/exploration", files)
	var handlers: int = 0
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		var body := _body_of(src, "func _on_roaming_monster_touched(")
		if body == "":
			continue
		handlers += 1
		assert_true(body.contains("MonsterSpawner.group_for_touch(monster_id, is_elite)"),
			"%s decides its own group instead of asking MonsterSpawner.group_for_touch" % path.get_file())
	## Derived, so a seventh overworld is judged too; the floor is what was true when the copies collapsed.
	assert_gte(handlers, 6, "CONTROL: the roamer-touch handlers were found (%d)" % handlers)


func test_no_one_carries_a_private_copy_of_the_rule() -> void:
	var files: Array = []
	_sources_under("res://src", files)
	assert_gt(files.size(), 100, "CONTROL: the source walk reached src/ (%d files)" % files.size())
	var copies: Array = []
	for path in files:
		if path.ends_with("/MonsterSpawner.gd"):
			continue
		var src := FileAccess.get_file_as_string(path)
		for sig in ["func _is_field_elite(", "func _elite_id(", "func group_for_touch(", "func is_field_elite(", "func elite_id("]:
			if src.contains(sig):
				copies.append("%s: %s" % [path.get_file(), sig])
	assert_eq(copies, [], "a private copy of the roamer-touch rule is back: %s" % [copies])


func test_an_ordinary_roamer_brings_one_to_three_of_its_own_kind() -> void:
	var sizes := {}
	for _i in SAMPLES:
		var g: Array = MonsterSpawner.group_for_touch(ORDINARY, false)
		sizes[g.size()] = true
		for e in g:
			assert_eq(e, ORDINARY, "a touched %s brought a %s" % [ORDINARY, e])
			if e != ORDINARY:
				return
	var seen: Array = sizes.keys()
	seen.sort()
	## All three sizes over 300 draws; a missing one means the extra roll was pinned or its range shrank.
	assert_eq(seen, [1, 2, 1 + MonsterSpawner.GROUP_EXTRA_MAX], "group sizes seen: %s" % [seen])


func test_an_elite_fights_alone() -> void:
	assert_false(MonsterSpawner.is_field_elite(ORDINARY), "CONTROL: %s must not be an authored elite" % ORDINARY)
	assert_true(MonsterSpawner.is_field_elite(AUTHORED_ELITE), "CONTROL: %s must be an authored elite" % AUTHORED_ELITE)
	for _i in 50:
		## Elite by the SPAWN (any species promoted to this world's rare) and elite by the SPECIES both fight alone.
		assert_eq(MonsterSpawner.group_for_touch(ORDINARY, true), [MonsterSpawner.elite_id(ORDINARY)],
			"a promoted elite brought company")
		assert_eq(MonsterSpawner.group_for_touch(AUTHORED_ELITE, false), [MonsterSpawner.elite_id(AUTHORED_ELITE)],
			"an authored elite brought company")


func test_the_elite_marker_is_added_once() -> void:
	var once: String = MonsterSpawner.elite_id(ORDINARY)
	assert_true(once.ends_with(EncounterSystem.ELITE_SUFFIX), "the marker was not added")
	assert_eq(MonsterSpawner.elite_id(once), once, "the marker was added twice")
