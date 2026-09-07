extends GutTest

## tick 214: defeat_cutscene_flags audit + runtime warning.
##
## Continues the silent-failure surface work from ticks 212-213.
##
## Flow:
##   1. Dungeon subclass declares defeat_cutscene_flags = [...]
##   2. DragonCave._trigger_boss_battle pushes into spec["constants"]
##   3. _apply_pending_boss_defeat writes each into game_constants
##   4. _get_pending_story_cutscene reads game_constants flags to
##      gate post-victory cutscenes
##
## Silent failure: a subclass typo (e.g. "cutscene_flag_wardin_..."
## instead of "warden_") sets the wrong flag at step 3, and step 4
## never finds it, so the post-defeat cutscene silently never plays.
## In production builds there's nothing to diagnose — just a
## missing narrative beat.
##
## Two defenses:
##
##   Runtime: _apply_pending_boss_defeat now push_warns when a
##   cutscene_flag_* arrives that isn't in _KNOWN_DEFEAT_CUTSCENE_FLAGS.
##
##   Static (CI): audit walks every defeat_cutscene_flags
##   declaration across src/maps/dungeons/ and asserts every value
##   is in the known set.

const GAME_LOOP := "res://src/GameLoop.gd"
const DUNGEONS_DIR := "res://src/maps/dungeons/"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Known set is wired ────────────────────────────────────────────────

func test_known_set_const_defined() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("const _KNOWN_DEFEAT_CUTSCENE_FLAGS := {"),
		"_KNOWN_DEFEAT_CUTSCENE_FLAGS const must exist on GameLoop")


func test_is_known_defeat_flag_helper_defined() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func _is_known_defeat_flag(flag: String) -> bool:"),
		"_is_known_defeat_flag helper must exist")


# ── Runtime warning fires on unknown flag ─────────────────────────────

func test_apply_pending_warns_on_unknown_cutscene_flag() -> void:
	var src := _read(GAME_LOOP)
	# Pin the warning surface in _apply_pending_boss_defeat.
	assert_true(src.contains("not referenced by any _get_pending_story_cutscene gate"),
		"_apply_pending_boss_defeat must push_warning when a cutscene_flag_* isn't in known set")
	assert_true(src.contains("subclass typo"),
		"warning should reference 'subclass typo' so devs immediately understand the likely cause")


func test_warning_only_fires_for_cutscene_flag_prefix() -> void:
	# Pin: the warning only fires when the constant name starts with
	# "cutscene_flag_". Other constants (e.g. dungeon-specific game
	# flags) shouldn't trigger the warning.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("c.begins_with(\"cutscene_flag_\")"),
		"warning gate must check 'cutscene_flag_' prefix to avoid false positives on non-cutscene constants")


# ── Static audit: every declared flag is in the known set ─────────────

func test_every_declared_defeat_flag_is_known() -> void:
	# Walk every dungeon .gd, extract every defeat_cutscene_flags = [...]
	# entry, and assert each appears in the known set.
	var known: Array[String] = []
	var gl_src := _read(GAME_LOOP)
	var const_idx: int = gl_src.find("const _KNOWN_DEFEAT_CUTSCENE_FLAGS")
	assert_gt(const_idx, -1)
	var const_end: int = gl_src.find("\n}", const_idx)
	var const_body: String = gl_src.substr(const_idx, const_end - const_idx)
	# Extract keys: `\t"cutscene_flag_X": true,`
	var cursor: int = 0
	while true:
		var key_idx: int = const_body.find("\"cutscene_flag_", cursor)
		if key_idx < 0:
			break
		var end_quote: int = const_body.find("\"", key_idx + 1)
		known.append(const_body.substr(key_idx + 1, end_quote - key_idx - 1))
		cursor = end_quote + 1

	assert_gt(known.size(), 4,
		"known-set sanity: must have > 4 known defeat flags (got %d)" % known.size())

	# Walk dungeon subclasses.
	var dir := DirAccess.open(DUNGEONS_DIR)
	assert_ne(dir, null)
	dir.list_dir_begin()
	var declared: Array[String] = []
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if not file_name.ends_with(".gd"):
			continue
		var content: String = FileAccess.get_file_as_string(DUNGEONS_DIR + file_name)
		# Find: `defeat_cutscene_flags = ["..."]` or multi-element arrays.
		var idx: int = content.find("defeat_cutscene_flags = [")
		while idx >= 0:
			var arr_start: int = idx + "defeat_cutscene_flags = [".length()
			var arr_end: int = content.find("]", arr_start)
			if arr_end < 0:
				break
			var arr_str: String = content.substr(arr_start, arr_end - arr_start)
			# Extract every "..."-quoted entry inside the brackets.
			var cc: int = 0
			while true:
				var qstart: int = arr_str.find("\"", cc)
				if qstart < 0:
					break
				var qend: int = arr_str.find("\"", qstart + 1)
				if qend < 0:
					break
				declared.append(arr_str.substr(qstart + 1, qend - qstart - 1))
				cc = qend + 1
			idx = content.find("defeat_cutscene_flags = [", arr_end)
	dir.list_dir_end()

	assert_gt(declared.size(), 3,
		"sanity: must find > 3 defeat_cutscene_flags declarations (got %d)" % declared.size())

	# Every declared flag must be in the known set.
	var unknown: Array[String] = []
	for d in declared:
		if not (d in known):
			unknown.append(d)
	assert_eq(unknown.size(), 0,
		"every defeat_cutscene_flags entry must be in _KNOWN_DEFEAT_CUTSCENE_FLAGS — missing: %s" % str(unknown))


# ── Cross-reference: known set entries are actually used in gates ─────

func test_every_known_flag_is_referenced_in_pending_check() -> void:
	# Pin the OTHER direction — every flag in the known set is
	# actually referenced by a flags.get(...) call in
	# _get_pending_story_cutscene. Otherwise the set has dead
	# entries that grant false confidence.
	var src := _read(GAME_LOOP)
	var const_idx: int = src.find("const _KNOWN_DEFEAT_CUTSCENE_FLAGS")
	var const_end: int = src.find("\n}", const_idx)
	var const_body: String = src.substr(const_idx, const_end - const_idx)
	var cursor: int = 0
	var unreferenced: Array[String] = []
	while true:
		var key_idx: int = const_body.find("\"cutscene_flag_", cursor)
		if key_idx < 0:
			break
		var end_quote: int = const_body.find("\"", key_idx + 1)
		var key: String = const_body.substr(key_idx + 1, end_quote - key_idx - 1)
		cursor = end_quote + 1
		# Look for `flags.get("KEY", ...)` somewhere in the file.
		var needle: String = "flags.get(\"" + key + "\""
		if not src.contains(needle):
			unreferenced.append(key)
	assert_eq(unreferenced.size(), 0,
		"_KNOWN_DEFEAT_CUTSCENE_FLAGS entries that no gate reads (dead set entries): %s" % str(unreferenced))


# ── Cross-pin: prior cutscene audits preserved ────────────────────────

func test_tick_212_completion_flag_audit_present() -> void:
	assert_true(FileAccess.file_exists("res://test/unit/test_cutscene_completion_flag_coverage_audit.gd"),
		"tick 212 completion flag audit must still exist")


func test_tick_213_boss_intro_audit_present() -> void:
	assert_true(FileAccess.file_exists("res://test/unit/test_boss_intro_cutscene_audit.gd"),
		"tick 213 boss intro audit must still exist")
