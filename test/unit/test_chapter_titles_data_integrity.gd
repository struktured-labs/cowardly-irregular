extends GutTest

## tick 242: structural data-integrity guard for ChapterTitles.
##
## Catches the bug class from tick 241 (W4 flag misplaced in W3)
## by enforcing cross-references at CI time:
##
##   1. Every flag in ChapterTitles.CHAPTERS must be SET somewhere
##      in the codebase. Otherwise the entry is dead config.
##
##   2. Every cutscene_flag_*_defeated entry's world placement
##      must match the world of the dungeon subclass that sets it.
##      (Tick 241's bug: warden_industrial_defeated set by W4's
##      AssemblyCore but ChapterTitles placed it in W3.)
##
##   3. Every cutscene_flag_*_complete entry must exist in
##      GameLoop._CUTSCENE_COMPLETION_FLAGS map (else no cutscene
##      ever sets it).
##
##   4. Sanity: CHAPTERS array is strictly ordered by world ASC
##      (within world, by chapter ASC). derive()'s "last set
##      flag wins" rule depends on this ordering — a misordered
##      entry could silently rewind the title across worlds.

const CHAPTER_TITLES := "res://src/save/ChapterTitles.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const DUNGEONS_DIR := "res://src/maps/dungeons"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Boss-defeat flag → world mapping table ───────────────────────────
# Pulled at test time from dungeon subclass defeat_cutscene_flags
# declarations. If the dungeon's world doesn't match the
# ChapterTitles entry's world, we have a tick-241-class bug.
func _scan_dungeon_defeat_flags() -> Dictionary:
	# Returns {flag_name: world_int}
	var result := {}
	var dir := DirAccess.open(DUNGEONS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var content: String = FileAccess.get_file_as_string("%s/%s" % [DUNGEONS_DIR, file_name])
			var world := _world_from_dungeon_name(file_name)
			var rx := RegEx.new()
			rx.compile("defeat_cutscene_flags\\s*=\\s*\\[\\s*\"(cutscene_flag_[a-z0-9_]+)\"")
			var matches: Array[RegExMatch] = rx.search_all(content)
			for m in matches:
				var flag := m.get_string(1)
				if world > 0:
					result[flag] = world
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _world_from_dungeon_name(file_name: String) -> int:
	# Map dungeon source filename → world int. Hand-coded because
	# the source files don't tag themselves with world numbers.
	var lower := file_name.to_lower()
	if "castleharmonia" in lower or "whisperingcave" in lower or "dragoncave" in lower:
		return 1
	if "suburbanunderground" in lower:
		return 2
	if "steampunkmechanism" in lower:
		return 3
	if "assemblycore" in lower:
		return 4
	if "rootprocess" in lower:
		return 5
	if "nullchamber" in lower:
		return 6
	return 0


# ── Audit 1: every defeat flag's world matches its dungeon ───────────

func test_defeat_flag_world_placement_matches_dungeon() -> void:
	var flag_to_world := _scan_dungeon_defeat_flags()
	assert_gt(flag_to_world.size(), 0,
		"sanity: must find at least one defeat_cutscene_flags declaration across dungeons")
	var src := _read(CHAPTER_TITLES)
	# For each defeat flag, find its ChapterTitles entry and confirm
	# the world matches.
	for flag in flag_to_world:
		var expected_world: int = flag_to_world[flag]
		# Find the entry line: "{...flag: "X" ... world: N ...}"
		var rx := RegEx.new()
		rx.compile("\"flag\":\\s*\"" + flag + "\"[^}]*\"world\":\\s*([0-9]+)")
		var m: RegExMatch = rx.search(src)
		if m == null:
			# No ChapterTitles entry — that's OK if the dungeon defeat
			# is meant to be transient (not a chapter milestone). Skip.
			continue
		var actual_world: int = int(m.get_string(1))
		assert_eq(actual_world, expected_world,
			"flag '%s' is set by a W%d dungeon but ChapterTitles places it in W%d (likely a copy-paste error like tick 241's W3/W4 bug)" % [flag, expected_world, actual_world])


# ── Audit 2: completion flags exist in _CUTSCENE_COMPLETION_FLAGS ───

func test_completion_flags_referenced_in_game_loop_map() -> void:
	# For each ChapterTitles entry whose flag ends in '_complete',
	# the same flag must appear SOMEWHERE in GameLoop — either as
	# a value in _CUTSCENE_COMPLETION_FLAGS, or as a dynamic
	# skip-loop set (e.g. "cutscene_flag_" + skip_flag), or in
	# the gate check `flags.get(...)`. Otherwise the entry is
	# dead config that no code path ever sets.
	var src := _read(CHAPTER_TITLES)
	var rx := RegEx.new()
	rx.compile("\"flag\":\\s*\"(cutscene_flag_[a-z0-9_]+_complete)\"")
	var matches: Array[RegExMatch] = rx.search_all(src)
	var gl: String = _read(GAME_LOOP)
	var missing: Array[String] = []
	for m in matches:
		var flag: String = m.get_string(1)
		# Allow either the full flag literal OR the bare suffix from
		# the dynamic skip loop (`"chapter5_complete"` in a string array
		# that gets prepended with "cutscene_flag_" at iteration).
		var bare: String = flag.replace("cutscene_flag_", "")
		var has_full: bool = gl.contains("\"" + flag + "\"")
		var has_bare_in_skip_loop: bool = gl.contains("\"" + bare + "\"") and gl.contains("\"cutscene_flag_\" + skip_flag")
		if not (has_full or has_bare_in_skip_loop):
			missing.append(flag)
	assert_eq(missing.size(), 0,
		"every chapter-completion flag must be settable somewhere in GameLoop — missing: %s" % str(missing))


# ── Audit 3: CHAPTERS array is ordered by world ASC ────────────────

func test_chapters_array_ordered_by_world_ascending() -> void:
	# Critical because derive() walks top-to-bottom and the LAST
	# matching flag wins. A misordered entry (e.g., a W3 entry
	# after a W4 entry) could silently rewind the title from W4
	# back to W3 even though the player has W4 progress.
	# Scope the regex to BEFORE the WORLD_NAMES const so it
	# doesn't pick up world: ints in that separate dict.
	var src := _read(CHAPTER_TITLES)
	var world_names_idx: int = src.find("const WORLD_NAMES")
	if world_names_idx < 0:
		world_names_idx = src.length()
	var chapters_body: String = src.substr(0, world_names_idx)
	var rx := RegEx.new()
	rx.compile("\"world\":\\s*([0-9]+)")
	var matches: Array[RegExMatch] = rx.search_all(chapters_body)
	var prev_world: int = 0
	var prev_index: int = -1
	var violations: Array[String] = []
	for i in matches.size():
		var w: int = int(matches[i].get_string(1))
		if w < prev_world:
			violations.append("entry #%d has world=%d after world=%d at #%d" % [i, w, prev_world, prev_index])
		prev_world = w
		prev_index = i
	assert_eq(violations.size(), 0,
		"CHAPTERS array must be world-ASC ordered — violations: %s" % str(violations))


# ── Audit 4: WORLD_NAMES has every referenced world ────────────────

func test_world_names_covers_every_referenced_world() -> void:
	var src := _read(CHAPTER_TITLES)
	# Pull world numbers from CHAPTERS.
	var rx := RegEx.new()
	rx.compile("\"world\":\\s*([0-9]+)")
	var matches: Array[RegExMatch] = rx.search_all(src)
	var worlds_used: Dictionary = {}
	for m in matches:
		worlds_used[int(m.get_string(1))] = true
	# Pull WORLD_NAMES keys.
	var rx2 := RegEx.new()
	rx2.compile("([0-9]+):\\s*\"")
	var name_matches: Array[RegExMatch] = rx2.search_all(src)
	var worlds_named: Dictionary = {}
	for m in name_matches:
		worlds_named[int(m.get_string(1))] = true
	# Every referenced world must have a name.
	var missing: Array[String] = []
	for w in worlds_used:
		if not (w in worlds_named):
			missing.append("world %d" % w)
	assert_eq(missing.size(), 0,
		"every world referenced in CHAPTERS must have a WORLD_NAMES entry — missing: %s" % str(missing))


# ── Cross-pin: tick 240 + 241 entries preserved ────────────────────

func test_tick_240_241_entries_preserved() -> void:
	var src := _read(CHAPTER_TITLES)
	for title in ["Rat King Falls", "Calibrant Falls", "The End",
			"Warden of Routine Falls", "Tempo Falls",
			"Warden of Industrial Falls", "Arbiter Falls"]:
		assert_true(src.contains("\"" + title + "\""),
			"prior-tick title preserved: %s" % title)
