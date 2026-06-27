extends GutTest

## tick 278: continuation of tick 277's W6 fix. Every overworld scene
## was reading a `w<N>_boss_defeated` story_flag — none of which were
## set anywhere in src/. The result: objective arrows and forward-
## world portals stayed gated on a flag that never fired.
##
## Each W1-W5 + W6 had the same bug class:
##   _get_objective_position: post-boss objective never activated
##   forward portal gate:     redundant alternative path (the
##                            is_world_unlocked check usually carried
##                            the day, but the explicit boss-flag
##                            check was always false)
##
## Fixed by reading the real game_constants cutscene_flag for each
## world's actual boss:
##   W1: cutscene_flag_world1_mordaine_defeated
##   W2: cutscene_flag_warden_suburban_defeated
##   W3: cutscene_flag_tempo_steampunk_defeated
##   W4: cutscene_flag_warden_industrial_defeated
##   W5: cutscene_flag_arbiter_futuristic_defeated
##   W6: cutscene_flag_world6_calibrant_defeat_complete  (tick 277)


# Files + the dead flag they referenced + the real flag that
# replaces it.
const REPLACEMENTS: Array = [
	{"file": "res://src/exploration/SuburbanOverworld.gd",
	 "dead": "w2_boss_defeated",
	 "real": "cutscene_flag_warden_suburban_defeated"},
	{"file": "res://src/exploration/SteampunkOverworld.gd",
	 "dead": "w3_boss_defeated",
	 "real": "cutscene_flag_tempo_steampunk_defeated"},
	{"file": "res://src/exploration/IndustrialOverworld.gd",
	 "dead": "w4_boss_defeated",
	 "real": "cutscene_flag_warden_industrial_defeated"},
	{"file": "res://src/exploration/FuturisticOverworld.gd",
	 "dead": "w5_boss_defeated",
	 "real": "cutscene_flag_arbiter_futuristic_defeated"},
	{"file": "res://src/exploration/OverworldScene.gd",
	 "dead": "w1_boss_defeated",
	 "real": "cutscene_flag_world1_mordaine_defeated"},
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Each W1-W5 file no longer references the dead story_flag ──────

func test_dead_w_boss_defeated_flags_removed() -> void:
	var survivors: Array[String] = []
	for entry in REPLACEMENTS:
		var src := _read(entry["file"])
		var needle: String = "get_story_flag(\"" + entry["dead"] + "\")"
		if src.contains(needle):
			survivors.append("%s still references %s" % [entry["file"], needle])
	assert_eq(survivors.size(), 0,
		"every w<N>_boss_defeated read must be replaced (none of these are written anywhere in src/): %s" % str(survivors))


# ── Each W1-W5 file now references the real flag ──────────────────

func test_real_cutscene_flags_now_referenced() -> void:
	var missing: Array[String] = []
	for entry in REPLACEMENTS:
		var src := _read(entry["file"])
		var needle: String = "game_constants.get(\"" + entry["real"] + "\""
		if not src.contains(needle):
			missing.append("%s missing real flag read %s" % [entry["file"], needle])
	assert_eq(missing.size(), 0,
		"each overworld must read its real boss flag from game_constants: %s" % str(missing))


# ── Sanity: the real flags all have writers somewhere in src/ ─────

func test_real_flags_all_have_writers() -> void:
	# Each real flag must be written by SOMETHING in src/ (otherwise
	# the fix is no better than the bug).
	for entry in REPLACEMENTS:
		var flag: String = entry["real"]
		var found: bool = _grep_writer(flag)
		assert_true(found,
			"real flag '%s' must have at least one writer in src/ (otherwise the post-boss path stays unreachable)" % flag)


# Walks src/ for any line that WRITES the flag (assignment or
# defeat_cutscene_flags listing).
func _grep_writer(flag: String) -> bool:
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk(dir, "res://src", flag)


func _walk(dir: DirAccess, base: String, flag: String) -> bool:
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
			if sub != null and _walk(sub, full, flag):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd"):
			var content: String = FileAccess.get_file_as_string(full)
			# Look for `"flag"]` (assignment), `"flag"` in
			# defeat_cutscene_flags, or `["flag"]` map references.
			if content.contains("\"" + flag + "\"]") or content.contains("\"" + flag + "\"") and (content.contains("defeat_cutscene_flags") or content.contains("game_constants[") or content.contains("constants")):
				# Verify this isn't a pure read by checking for "=" near a quoted form.
				if content.contains("\"" + flag + "\"] = true") \
						or content.contains("\"" + flag + "\"") and content.contains("defeat_cutscene_flags = ["):
					dir.list_dir_end()
					return true
	dir.list_dir_end()
	return false
