extends GutTest

## tick 359: SoundManager._get_current_world_suffix recognizes the
## canonical `<world>_overworld` map_id forms (suburban_overworld,
## steampunk_overworld, etc.) alongside the legacy `overworld_<world>`
## strings.
##
## Pre-fix the match arms only listed the legacy reversed form:
##   "overworld_suburban", "maple_heights_village", "suburban_dungeon"
##
## But GameLoop._on_area_transition (line ~3856) calls
##   SoundManager.play_area_music(_current_map_id)
##
## passing the CANONICAL `<world>_overworld` form (suburban_overworld
## etc., per the map_ids defined throughout the codebase). The
## canonical-form call fell through to the `_:` arm and returned the
## cached `_current_world_suffix` (initialized to "medieval").
##
## Result: every battle in suburban/steampunk/industrial/futuristic/
## abstract overworlds used MEDIEVAL battle music regardless of
## where the player actually was — there's actual world-specific
## battle music in the manifest (battle_suburban, battle_steampunk,
## battle_industrial, battle_digital, battle_abstract) that the
## player never heard during normal play.

const SOUND_MANAGER_PATH := "res://src/audio/SoundManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: canonical map_ids in arms ───────────────────────────

func test_canonical_map_ids_in_arms() -> void:
	var src := _read(SOUND_MANAGER_PATH)
	var fn_idx: int = src.find("func _get_current_world_suffix")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	for canonical in [
		"suburban_overworld",
		"steampunk_overworld",
		"industrial_overworld",
		"futuristic_overworld",
		"abstract_overworld",
	]:
		assert_true(body.contains("\"%s\"" % canonical),
			"_get_current_world_suffix must include canonical map_id '%s'" % canonical)


# ── Source pin: legacy arms preserved (don't regress them) ──────────

func test_legacy_arms_preserved() -> void:
	# The legacy `overworld_<world>` form is still called by the
	# Overworld scenes' explicit play_area_music calls. Must stay.
	var src := _read(SOUND_MANAGER_PATH)
	var fn_idx: int = src.find("func _get_current_world_suffix")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	for legacy in [
		"overworld_suburban",
		"overworld_steampunk",
		"overworld_industrial",
		"overworld_futuristic",
		"overworld_abstract",
	]:
		assert_true(body.contains("\"%s\"" % legacy),
			"legacy arm '%s' must remain — Overworld scenes still call play_area_music with this form" % legacy)


# ── Behavioral: canonical map_ids return the right suffix ───────────

func test_canonical_returns_correct_suffix() -> void:
	assert_not_null(SoundManager, "SoundManager autoload required")
	if SoundManager == null:
		return

	var prior_area: String = SoundManager._current_area
	var prior_suffix: String = SoundManager._current_world_suffix

	# Pin: ask the resolver directly via _current_area state. The
	# function reads _current_area and returns the mapped suffix.
	for pair in [
		["suburban_overworld", "suburban"],
		["steampunk_overworld", "steampunk"],
		["industrial_overworld", "industrial"],
		["futuristic_overworld", "digital"],
		["abstract_overworld", "abstract"],
	]:
		var area: String = pair[0]
		var expected: String = pair[1]
		SoundManager._current_area = area
		var got: String = SoundManager._get_current_world_suffix()
		assert_eq(got, expected,
			"canonical area '%s' must return suffix '%s' (was returning '%s' — falling through to cached medieval default)" % [area, expected, got])

	# Restore.
	SoundManager._current_area = prior_area
	SoundManager._current_world_suffix = prior_suffix


# ── Behavioral: castle_harmonia stays medieval ──────────────────────

func test_castle_harmonia_is_medieval() -> void:
	# Tick 359 also added castle_harmonia (W1 final boss arena) so its
	# battle music doesn't fall through to the cached suffix from
	# whatever the player visited last.
	assert_not_null(SoundManager, "SoundManager autoload required")
	if SoundManager == null:
		return
	var prior_area: String = SoundManager._current_area
	SoundManager._current_area = "castle_harmonia"
	assert_eq(SoundManager._get_current_world_suffix(), "medieval",
		"castle_harmonia must map to 'medieval' explicitly")
	SoundManager._current_area = prior_area
