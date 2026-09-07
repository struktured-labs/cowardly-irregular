extends GutTest

## tick 332: cutscene flag-naming convention is consistent across
## _step_choice (writer) and _step_branch (reader).
##
## Pre-tick-332 the convention was:
##   - _step_set_flag writes `cutscene_flag_<name>` (CutsceneDirector
##     line ~627).
##   - _step_branch reads `cutscene_flag_<name>` (line ~1004).
##   - _set_choice_flag (added in tick 331) wrote the BARE name —
##     so any branch step keyed on a choice flag never fired.
##
## That breaks the whole "choice → flag → branch" loop: the player
## picks an option, the cutscene appears to record it, but a
## downstream branch reading the flag sees false and goes to the
## fallback (if_false / default) path. The choice was diegetically
## meaningless even after tick 331 implemented the step type.
##
## Fix prepends "cutscene_flag_" in _set_choice_flag to match the
## set_flag / branch convention. Test pins the source pattern so the
## prefix can't drift.

const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: _set_choice_flag uses the prefix ────────────────────

func test_set_choice_flag_uses_prefix() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _set_choice_flag")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"cutscene_flag_\" + flag_name"),
		"_set_choice_flag must prepend 'cutscene_flag_' to match _step_set_flag and _step_branch")


# ── Source pin: cross-step prefix consistency ───────────────────────

func test_three_step_handlers_share_prefix() -> void:
	# _step_set_flag, _set_choice_flag (writers) and _step_branch
	# (reader) must all use the same "cutscene_flag_" prefix. If any
	# one drifts, choice → set_flag → branch loops break.
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	# set_flag writer.
	var sf_idx: int = src.find("func _step_set_flag")
	var sf_next: int = src.find("\nfunc ", sf_idx + 1)
	var sf_body: String = src.substr(sf_idx, sf_next - sf_idx) if sf_next > 0 else src.substr(sf_idx)
	assert_true(sf_body.contains("\"cutscene_flag_\" + flag"),
		"_step_set_flag must use cutscene_flag_ prefix (existing convention since pre-tick-331)")

	# choice writer.
	var cf_idx: int = src.find("func _set_choice_flag")
	var cf_next: int = src.find("\nfunc ", cf_idx + 1)
	var cf_body: String = src.substr(cf_idx, cf_next - cf_idx) if cf_next > 0 else src.substr(cf_idx)
	assert_true(cf_body.contains("\"cutscene_flag_\" + flag_name"),
		"_set_choice_flag must use cutscene_flag_ prefix (tick 332)")

	# Branch reader.
	var br_idx: int = src.find("func _step_branch")
	var br_next: int = src.find("\nfunc ", br_idx + 1)
	var br_body: String = src.substr(br_idx, br_next - br_idx) if br_next > 0 else src.substr(br_idx)
	assert_true(br_body.contains("\"cutscene_flag_\" + flag"),
		"_step_branch must read cutscene_flag_ prefix (existing convention)")


# ── Behavioral: choice → branch loop closes correctly ───────────────

func test_choice_flag_readable_by_branch_lookup() -> void:
	# End-to-end: write via _set_choice_flag, read via the same key
	# pattern _step_branch uses. If the conventions match, the flag is
	# visible at the read site.
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	var director: Object = script.new()
	add_child_autofree(director)

	var bare_flag: String = "world6_orrery_response_tick_332_loop"
	var prefixed_key: String = "cutscene_flag_" + bare_flag
	# Clean slate.
	GameState.game_constants.erase(prefixed_key)

	# Write via choice path.
	director._set_choice_flag({"text": "Test", "flag": bare_flag})

	# Read using the same lookup _step_branch would do (line ~1004).
	var read_value: bool = false
	if GameState.game_constants.has("cutscene_flag_" + bare_flag):
		read_value = bool(GameState.game_constants["cutscene_flag_" + bare_flag])
	assert_true(read_value,
		"After _set_choice_flag, the cutscene_flag_<name> lookup _step_branch performs must see true. If this fails the choice→branch loop is broken again.")

	# Cleanup.
	GameState.game_constants.erase(prefixed_key)
