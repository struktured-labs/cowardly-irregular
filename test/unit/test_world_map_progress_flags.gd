extends GutTest

## tick 272: WorldMapMenu.PROGRESS_FLAGS boss-defeat placement audit.
##
## Same bug class as tick 241's ChapterTitles fix: W3's progress list
## referenced `cutscene_flag_warden_industrial_defeated` (the W4
## Industrial Warden boss flag) — so beating the W4 boss would tick
## the W3 progress bar instead of W4's. Pre-fix W2/W4/W5 were also
## missing their own boss-defeat flags from their progress lists,
## and W6 missed the Calibrant.
##
## Audits:
##   1. Each world's PROGRESS_FLAGS list includes its own boss-defeat
##      flag (so the bar advances when the player beats the boss).
##   2. No world's PROGRESS_FLAGS list contains another world's boss
##      flag (catches the tick-241/272 misplacement pattern).
##   3. Every flag in PROGRESS_FLAGS has an emitter in src/ (sanity).

const WORLD_MAP_MENU := "res://src/ui/WorldMapMenu.gd"


# Boss-defeat flag for each world. Boss IDs derived from the dungeon
# subclass that emits them (verified at tick 241).
const WORLD_BOSS_FLAG: Dictionary = {
	1: "cutscene_flag_world1_mordaine_defeated",
	2: "cutscene_flag_warden_suburban_defeated",
	3: "cutscene_flag_tempo_steampunk_defeated",
	4: "cutscene_flag_warden_industrial_defeated",
	5: "cutscene_flag_arbiter_futuristic_defeated",
	6: "cutscene_flag_world6_calibrant_defeat_complete",
}


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# Quick parse: returns {world_int: Array[String of flags]}.
func _parse_progress_flags() -> Dictionary:
	var menu_script: GDScript = load(WORLD_MAP_MENU)
	# The const is accessible directly on the class.
	return menu_script.PROGRESS_FLAGS


# ── Audit 1: each world includes its own boss flag ────────────────

func test_each_world_includes_its_boss_defeat_flag() -> void:
	var pf: Dictionary = _parse_progress_flags()
	var missing: Array[String] = []
	for world in WORLD_BOSS_FLAG:
		var boss_flag: String = WORLD_BOSS_FLAG[world]
		var list: Array = pf.get(world, [])
		if not (boss_flag in list):
			missing.append("W%d missing boss flag %s" % [world, boss_flag])
	assert_eq(missing.size(), 0,
		"each world's progress list must include its own boss-defeat flag (so the bar ticks when the boss falls): %s" % str(missing))


# ── Audit 2: no world contains another world's boss flag ──────────

func test_no_world_contains_other_worlds_boss_flag() -> void:
	# Catches the tick-241/272 misplacement pattern.
	var pf: Dictionary = _parse_progress_flags()
	var violations: Array[String] = []
	for world in WORLD_BOSS_FLAG:
		var own_boss: String = WORLD_BOSS_FLAG[world]
		for other_world in WORLD_BOSS_FLAG:
			if other_world == world:
				continue
			var foreign_boss: String = WORLD_BOSS_FLAG[other_world]
			var list: Array = pf.get(world, [])
			if foreign_boss in list:
				violations.append("W%d contains W%d's boss flag '%s'" % [world, other_world, foreign_boss])
	assert_eq(violations.size(), 0,
		"W3 historically had W4's boss flag (tick 241/272 fix). No world's list may reference another world's boss: %s" % str(violations))


# ── Audit 3: every progress flag has an emitter (sanity) ──────────

func test_every_progress_flag_has_emitter() -> void:
	var pf: Dictionary = _parse_progress_flags()
	var dead: Array[String] = []
	for world in pf:
		for flag in pf[world]:
			if not _flag_emitted(str(flag)):
				dead.append("W%d: %s" % [world, flag])
	assert_eq(dead.size(), 0,
		"every PROGRESS_FLAGS entry must be emitted somewhere in src/ (else bar can never advance): %s" % str(dead))


func _flag_emitted(flag: String) -> bool:
	# Walk src/ for the literal quoted flag name outside WorldMapMenu.gd.
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk_for(dir, "res://src", "\"" + flag + "\"")


func _walk_for(dir: DirAccess, base: String, needle: String) -> bool:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var sub := DirAccess.open(full)
			if sub != null and _walk_for(sub, full, needle):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("WorldMapMenu.gd"):
			var content: String = FileAccess.get_file_as_string(full)
			if content.contains(needle):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false


# ── Cross-pin: tick 241 ChapterTitles fix preserved ────────────────

func test_tick_241_chapter_titles_w3_still_uses_tempo() -> void:
	# WorldMapMenu and ChapterTitles share the same boss-flag truth.
	# Defensively pin tick 241's ChapterTitles fix doesn't drift back.
	var ct: String = FileAccess.get_file_as_string("res://src/save/ChapterTitles.gd")
	assert_true(ct.contains("cutscene_flag_tempo_steampunk_defeated"),
		"ChapterTitles must still use cutscene_flag_tempo_steampunk_defeated for W3 (tick 241 fix)")
