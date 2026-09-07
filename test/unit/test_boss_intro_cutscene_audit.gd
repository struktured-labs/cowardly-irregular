extends GutTest

## tick 213 + 2026-07-13 director-lookup fix: audit boss_cutscene_id
## wiring across all DragonCave subclasses and pin the correct director
## routing. CutsceneDirector is GameLoop-owned, NOT an autoload — the
## previous `/root/CutsceneDirector` lookup silently returned null and
## every W1 boss intro (Mordaine + 4 dragons) fell back to console print.
## Same class as the TallyWall bug (2026-07-08). Fix routes through
## GameLoop.get_cutscene_director(), matching QuestSystem and TallyWall.
##
## Silent-failure paths that still fall to console (each push_warnings):
##   (a) boss_cutscene_id set, JSON missing on disk
##   (b) GameLoop.get_cutscene_director() returned null
##   (c) director lacks play_cutscene method
##
## Static coverage audit verifies every subclass's boss_cutscene_id
## points to a real JSON file on disk.

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"
const DUNGEONS_DIR := "res://src/maps/dungeons/"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Loud-fail surfaces ────────────────────────────────────────────────

func test_missing_json_pushes_warning() -> void:
	var src := _read(DRAGON_CAVE)
	# Pin the file-missing branch's push_warning.
	assert_true(src.contains("[DragonCave] boss_cutscene_id='%s' but %s does not exist"),
		"_show_boss_intro must push_warning when JSON file is missing")
	assert_true(src.contains("falling back to console intro"),
		"warning must state the consequence (console fallback)")


func test_null_director_pushes_warning() -> void:
	var src := _read(DRAGON_CAVE)
	assert_true(src.contains("GameLoop.get_cutscene_director() returned null"),
		"_show_boss_intro must push_warning when the director is null")


func test_missing_play_cutscene_method_pushes_warning() -> void:
	var src := _read(DRAGON_CAVE)
	assert_true(src.contains("but CutsceneDirector lacks play_cutscene method"),
		"_show_boss_intro must push_warning when director lacks play_cutscene")


func test_director_routes_through_game_loop() -> void:
	# 2026-07-13 director-lookup fix: CutsceneDirector is NOT autoloaded, so
	# `/root/CutsceneDirector` returned null and every boss intro silently
	# fell back to console print. The routing now goes through GameLoop's
	# lazy accessor (matches QuestSystem and TallyWall).
	var src := _read(DRAGON_CAVE)
	assert_false(src.contains("get_node_or_null(\"/root/CutsceneDirector\")"),
		"stale /root/CutsceneDirector lookup must not resurface")
	var fn_idx := src.find("func _show_boss_intro")
	assert_gt(fn_idx, 0, "boss intro function present")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_cutscene_director"),
		"_show_boss_intro reaches GameLoop.get_cutscene_director()")


# ── Static coverage audit: each subclass's id points to an existing file ──

func test_every_subclass_boss_cutscene_points_to_existing_json() -> void:
	# Walk every .gd file in the dungeons dir, extract any
	# `boss_cutscene_id = "..."` assignment, and verify the
	# corresponding JSON exists.
	var dir := DirAccess.open(DUNGEONS_DIR)
	assert_ne(dir, null, "must be able to open dungeons dir")
	dir.list_dir_begin()
	var missing: Array[String] = []
	var found_count: int = 0
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if not file_name.ends_with(".gd"):
			continue
		var path: String = DUNGEONS_DIR + file_name
		var content: String = FileAccess.get_file_as_string(path)
		if content == "":
			continue
		# Find every `boss_cutscene_id = "..."` literal (skip the base
		# class's `var boss_cutscene_id: String = ""` declaration).
		var cursor: int = 0
		while true:
			var idx: int = content.find("boss_cutscene_id = \"", cursor)
			if idx < 0:
				break
			var quote_start: int = idx + "boss_cutscene_id = \"".length()
			var quote_end: int = content.find("\"", quote_start)
			if quote_end < 0:
				break
			var id: String = content.substr(quote_start, quote_end - quote_start)
			cursor = quote_end + 1
			if id == "":  # base class declaration
				continue
			found_count += 1
			var json_path: String = "res://data/cutscenes/%s.json" % id
			if not FileAccess.file_exists(json_path):
				missing.append("%s → '%s' (looked for %s)" % [file_name, id, json_path])
	dir.list_dir_end()
	assert_gt(found_count, 5,
		"sanity: must find > 5 boss_cutscene_id assignments across subclasses (got %d)" % found_count)
	assert_eq(missing.size(), 0,
		"every boss_cutscene_id must point to an existing JSON: missing — %s" % str(missing))


# ── Existing boss intros still wired ───────────────────────────────────

func test_w1_dragons_have_intros() -> void:
	# Pin: the 4 W1 dragons still have boss_cutscene_id wired.
	# A future refactor that orphans one of these would tank the
	# W1 narrative experience.
	for cave_file in ["FireDragonCave.gd", "IceDragonCave.gd",
			"LightningDragonCave.gd", "ShadowDragonCave.gd"]:
		var path: String = DUNGEONS_DIR + cave_file
		var content: String = FileAccess.get_file_as_string(path)
		assert_true(content.contains("boss_cutscene_id = \""),
			"%s must set boss_cutscene_id" % cave_file)


func test_mordaine_intro_still_wired() -> void:
	# Pin: CastleHarmonia (W1 final) sets boss_cutscene_id.
	var content: String = FileAccess.get_file_as_string(DUNGEONS_DIR + "CastleHarmonia.gd")
	assert_true(content.contains("boss_cutscene_id = \"world1_mordaine_intro\""),
		"CastleHarmonia must wire world1_mordaine_intro")


# ── Cross-pin: console fallback path still in place ───────────────────

func test_console_fallback_preserved() -> void:
	# The console fallback IS the safety net when JSON is missing —
	# we want a warning + still play the fight (not crash). Confirm
	# the fallback still runs.
	var src := _read(DRAGON_CAVE)
	assert_true(src.contains("=== BOSS ENCOUNTER ==="),
		"console fallback header still printed (graceful degradation preserved)")
	assert_true(src.contains("await get_tree().create_timer(2.0).timeout"),
		"console fallback 2s delay preserved (gives time to read)")


# ── Cross-pin: tick 212 cutscene flag audit still in place ────────────

func test_tick_212_completion_flag_audit_present() -> void:
	# The boss-intro fix complements tick 212's _CUTSCENE_COMPLETION_FLAGS
	# audit. Verify the prior tick's test is still around so this
	# tick doesn't accidentally remove it.
	assert_true(FileAccess.file_exists("res://test/unit/test_cutscene_completion_flag_coverage_audit.gd"),
		"tick 212 coverage audit must still exist")
