extends GutTest

## tick 220: shared _set_cutscene_flag_and_mirror helper +
## refactor of every direct game_constants write to use it.
##
## Pre-fix the cutscene_flag → story_flag mirror lived ONLY at the
## end of _play_story_cutscene. Every other site that wrote
## `GameState.game_constants["cutscene_flag_X"] = true` directly
## silently skipped the mirror:
##
##   _get_pending_story_cutscene auto-advance gates (6 sites):
##     - cutscene_flag_chapter2_complete
##     - cutscene_flag_<chapter5/7/8/9>_complete
##     - cutscene_flag_arbiter_suburban_defeated
##     - cutscene_flag_curator_suburban_defeated
##     - cutscene_flag_world<2..5>_complete
##   _apply_pending_boss_defeat ([constants] write):
##     - Every boss defeat flag pushed via spec["constants"]
##
## Player saw quest-log lines stay yellow ("Speak with Elder
## Theron") even after the cutscene fired — same 2026-06-04 bug
## class that triggered the original mirror's introduction. Now
## it occurs across boss defeats, chapter auto-advances, and
## world completions.
##
## Fix: one helper. All 9 writes call it. The mirror is no longer
## skippable — adding it to the helper means future sites get it
## for free.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Helper exists with correct shape ──────────────────────────────────

func test_helper_function_defined() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func _set_cutscene_flag_and_mirror(flag: String) -> void:"),
		"_set_cutscene_flag_and_mirror helper must exist")


func test_helper_writes_game_constants() -> void:
	var src := _read(GAME_LOOP)
	var fn_idx: int = src.find("func _set_cutscene_flag_and_mirror")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("GameState.game_constants[flag] = true"),
		"helper must write to game_constants[flag]")


func test_helper_mirrors_to_story_flags() -> void:
	var src := _read(GAME_LOOP)
	var fn_idx: int = src.find("func _set_cutscene_flag_and_mirror")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if flag.begins_with(\"cutscene_flag_\"):"),
		"helper must gate the mirror on cutscene_flag_ prefix")
	assert_true(body.contains("GameState.set_story_flag(bare)"),
		"helper must mirror to story_flags via set_story_flag(bare)")


func test_helper_handles_empty_flag() -> void:
	# Pin: defensive guard against empty flag (e.g., a missing map
	# entry from tick 212 audit returns ""). The helper short-circuits.
	var src := _read(GAME_LOOP)
	var fn_idx: int = src.find("func _set_cutscene_flag_and_mirror")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if not GameState or flag == \"\":"),
		"helper must guard against missing GameState OR empty flag")


# ── Call sites use the helper ────────────────────────────────────────

func test_all_known_call_sites_use_helper() -> void:
	# Pin: every refactored site calls the helper with the correct
	# flag name. This is the substantive coverage check.
	var src := _read(GAME_LOOP)
	var sites: Array[String] = [
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_chapter2_complete\")",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_\" + skip_flag)",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_arbiter_suburban_defeated\")",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_curator_suburban_defeated\")",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_world2_complete\")",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_world3_complete\")",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_world4_complete\")",
		"_set_cutscene_flag_and_mirror(\"cutscene_flag_world5_complete\")",
		"_set_cutscene_flag_and_mirror(str(c))",
		"_set_cutscene_flag_and_mirror(completion_flag)",
	]
	for site in sites:
		assert_true(src.contains(site),
			"expected call site: %s" % site)


# ── Negative pins: pre-fix bare writes gone ───────────────────────────

func test_no_more_bare_world_complete_writes() -> void:
	var src := _read(GAME_LOOP)
	for flag in ["cutscene_flag_world2_complete", "cutscene_flag_world3_complete",
			"cutscene_flag_world4_complete", "cutscene_flag_world5_complete"]:
		var bare: String = "GameState.game_constants[\"" + flag + "\"] = true"
		assert_false(src.contains(bare),
			"bare write must be gone: %s" % bare)


func test_no_more_bare_chapter_auto_advance_writes() -> void:
	var src := _read(GAME_LOOP)
	for flag in ["cutscene_flag_chapter2_complete",
			"cutscene_flag_arbiter_suburban_defeated",
			"cutscene_flag_curator_suburban_defeated"]:
		var bare: String = "GameState.game_constants[\"" + flag + "\"] = true"
		assert_false(src.contains(bare),
			"bare write must be gone: %s" % bare)


func test_no_more_skip_flag_dynamic_bare_write() -> void:
	# Negative pin: the dynamic loop's bare write is gone.
	var src := _read(GAME_LOOP)
	assert_false(src.contains("GameState.game_constants[\"cutscene_flag_\" + skip_flag] = true"),
		"dynamic skip_flag bare write must be gone")


func test_no_more_pending_boss_defeat_bare_write() -> void:
	# _apply_pending_boss_defeat now routes through the helper.
	var src := _read(GAME_LOOP)
	var fn_idx: int = src.find("func _apply_pending_boss_defeat")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Confirm the `for c in spec.get("constants", ...)` loop now calls helper.
	assert_true(body.contains("_set_cutscene_flag_and_mirror(str(c))"),
		"_apply_pending_boss_defeat's constants loop must call helper")
	# AND the old `GameState.game_constants[c] = true` direct write
	# is replaced.
	assert_false(body.contains("GameState.game_constants[c] = true"),
		"bare GameState.game_constants[c] = true must be gone")


# ── Allowed exceptions (still bare writes, intentional) ───────────────

func test_dungeon_flags_nested_write_preserved() -> void:
	# Pin: the dungeon_flags[df] = true write is a NESTED dict
	# assignment — not a cutscene_flag_*. It should NOT be routed
	# through the helper. Confirm it's preserved.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GameState.game_constants[\"dungeon_flags\"][df] = true"),
		"nested dungeon_flags write preserved (not a cutscene_flag_*)")


func test_game_complete_flag_preserved() -> void:
	# Pin: world6_ending's game_complete flag is a non-cutscene_flag_
	# constant. It still uses a direct write — verify it's preserved
	# (not in scope for the cutscene_flag_ helper).
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GameState.game_constants[\"game_complete\"] = true"),
		"game_complete (non-cutscene_flag_) direct write preserved")
	assert_true(src.contains("GameState.set_story_flag(\"game_complete\")"),
		"game_complete also mirrors to story_flag directly (already correct)")


# ── Cross-pin: prior cutscene-flag audit work preserved ───────────────

func test_tick_212_completion_flag_audit_present() -> void:
	assert_true(FileAccess.file_exists("res://test/unit/test_cutscene_completion_flag_coverage_audit.gd"),
		"tick 212 audit must still exist")


func test_tick_214_defeat_flag_audit_present() -> void:
	assert_true(FileAccess.file_exists("res://test/unit/test_defeat_cutscene_flag_audit.gd"),
		"tick 214 audit must still exist")
