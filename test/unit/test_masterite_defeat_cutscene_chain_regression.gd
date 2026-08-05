extends GutTest

## Regression 2026-08-05: world5_curator_defeat could never play.
##
## Four masterite dungeons, four post-victory defeat cutscenes. Three played. The Null
## Chamber declared no `defeat_cutscene_flags`, so nothing ever wrote the flag its scene
## waits on — and world5_curator_defeat is the LARGEST of the four (35 steps) and the
## ONLY one with a composed, titled, git-tracked score (cutscene_w6_memory_is_love).
## Three unscored scenes played; the scored one could not.
##
## The chain has FOUR parts and a partial fix is worse than none:
##   1  the dungeon declares defeat_cutscene_flags
##   2  a _get_pending_story_cutscene gate reads that flag and returns the scene
##   3  _CUTSCENE_COMPLETION_FLAGS maps the scene -> its completion flag
##   4  _KNOWN_DEFEAT_CUTSCENE_FLAGS contains the declared flag
##
## Part 3 is why this is a regression test and not a one-liner. Without it the completion
## flag is never written, the gate stays true forever, and the scene REPLAYS ON EVERY GATE
## CHECK — the Elder Theron loop bug. GameLoop's own warning text says so, and a lane
## costed this as "one line" tonight having read that warning earlier the same evening.
##
## Derived from the dungeon scripts, never a hand-list: a fifth masterite dungeon added
## without the full chain fails here rather than shipping a scene nobody can reach.

const GAMELOOP := "res://src/GameLoop.gd"
const DUNGEON_DIR := "res://src/maps/dungeons"


func _gameloop_consts() -> Dictionary:
	var script := load(GAMELOOP)
	assert_not_null(script, "GameLoop must load — it owns the gate and both flag maps")
	return script.get_script_constant_map()


## dungeon file -> the defeat flags it declares. Derived, so a new dungeon is covered.
func _declared_defeat_flags() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(DUNGEON_DIR)
	assert_not_null(dir, "dungeons dir must open")
	var rx := RegEx.new()
	rx.compile('defeat_cutscene_flags\\s*=\\s*\\[([^\\]]*)\\]')
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f])
		var m := rx.search(src)
		if m == null:
			continue
		var flags: Array = []
		var inner := RegEx.new()
		inner.compile('"([a-z0-9_]+)"')
		for fm in inner.search_all(m.get_string(1)):
			flags.append(fm.get_string(1))
		if not flags.is_empty():
			out[f] = flags
	return out


## Dungeons whose boss is a masterite — the family this chain belongs to.
func _masterite_dungeons() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	assert_not_null(dir, "dungeons dir must open")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f])
		if src.contains('boss_id = "masterite_'):
			out.append(f)
	return out


func test_every_masterite_dungeon_declares_a_defeat_flag() -> void:
	# THE regression. NullChamber was the one that didn't.
	var masterite := _masterite_dungeons()
	assert_gt(masterite.size(), 3,
		"POSITIVE CONTROL: several masterite dungeons must be found — a small number makes this vacuous")
	var declared := _declared_defeat_flags()
	var missing: Array = []
	for f in masterite:
		if not declared.has(f):
			missing.append(f)
	assert_eq(missing.size(), 0,
		"these masterite dungeons declare no defeat_cutscene_flags, so their defeat cutscene can never play: %s" % str(missing))


func test_every_declared_defeat_flag_is_known() -> void:
	# Part 4. The existing audit reds on an unknown flag; this names it first.
	var known: Dictionary = _gameloop_consts().get("_KNOWN_DEFEAT_CUTSCENE_FLAGS", {})
	assert_gt(known.size(), 4,
		"POSITIVE CONTROL: _KNOWN_DEFEAT_CUTSCENE_FLAGS must be readable — if renamed, every flag below reads as unknown")
	var unknown: Array = []
	for f in _declared_defeat_flags():
		for flag in _declared_defeat_flags()[f]:
			if not known.has(flag):
				unknown.append("%s declares %s" % [f, flag])
	assert_eq(unknown.size(), 0,
		"declared defeat flags absent from _KNOWN_DEFEAT_CUTSCENE_FLAGS: %s" % str(unknown))


func test_every_defeat_scene_terminates() -> void:
	# Part 3, and the dangerous one. A scene reachable but absent from the completion map
	# sets no flag on finish, so its gate stays true and it REPLAYS FOREVER.
	var consts := _gameloop_consts()
	var completion: Dictionary = consts.get("_CUTSCENE_COMPLETION_FLAGS", {})
	assert_gt(completion.size(), 20,
		"POSITIVE CONTROL: the completion map must be readable — a regex over source counts 8 of 55")
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var rx := RegEx.new()
	rx.compile('return "(world[0-9]_[a-z0-9_]*defeat)"')
	var returned: Array = []
	for m in rx.search_all(src):
		if not returned.has(m.get_string(1)):
			returned.append(m.get_string(1))
	assert_gt(returned.size(), 2,
		"POSITIVE CONTROL: several defeat scenes must be returned by gates — got %s" % str(returned))
	var looping: Array = []
	for scene in returned:
		if not completion.has(scene):
			looping.append(scene)
	assert_eq(looping.size(), 0,
		"these defeat cutscenes are returned by a gate but absent from _CUTSCENE_COMPLETION_FLAGS — each will REPLAY on every gate check: %s" % str(looping))


func test_the_curator_chain_is_complete_end_to_end() -> void:
	# The specific scene this regression is named for, all four parts at once.
	var consts := _gameloop_consts()
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var null_chamber := FileAccess.get_file_as_string("%s/NullChamber.gd" % DUNGEON_DIR)
	assert_true(null_chamber.contains("cutscene_flag_curator_abstract_defeated"),
		"part 1: NullChamber must declare the defeat flag")
	assert_true(src.contains('return "world5_curator_defeat"'),
		"part 2: a gate must return the scene")
	assert_true((consts.get("_CUTSCENE_COMPLETION_FLAGS", {}) as Dictionary).has("world5_curator_defeat"),
		"part 3: the scene must map to a completion flag or it replays forever")
	assert_true((consts.get("_KNOWN_DEFEAT_CUTSCENE_FLAGS", {}) as Dictionary).has("cutscene_flag_curator_abstract_defeated"),
		"part 4: the declared flag must be known to the audit")


func test_the_scene_exists_and_is_safe_to_play() -> void:
	# It grants no item — the inert-relic trap that stopped the fragment wiring does not
	# apply here, and that is worth pinning rather than remembering.
	var path := "res://data/cutscenes/world5_curator_defeat.json"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "the scene must parse")
	var steps: Array = (parsed as Dictionary).get("steps", [])
	assert_gt(steps.size(), 10, "the scene must have real content, got %d steps" % steps.size())
	var grants: Array = []
	for s in steps:
		if s is Dictionary and str(s.get("type", "")) == "grant_item":
			grants.append(str(s.get("item", "")))
	assert_eq(grants.size(), 0,
		"this scene must not grant items — every fragment relic is effects={} with an unauthored passive, so granting one ships visible broken content: %s" % str(grants))


func test_the_derivations_discriminate() -> void:
	# NEGATIVE CONTROL. Both derivations must reject an invented member, else the
	# assertions above pass on anything.
	assert_false(_declared_defeat_flags().has("ZzzNotADungeon.gd"),
		"the declaration sweep must not match an invented file")
	assert_false(_masterite_dungeons().has("ZzzNotADungeon.gd"),
		"the masterite sweep must not match an invented file")
	var known: Dictionary = _gameloop_consts().get("_KNOWN_DEFEAT_CUTSCENE_FLAGS", {})
	assert_false(known.has("cutscene_flag_zzz_invented_defeated"),
		"the known-flag const must not contain an invented flag")
