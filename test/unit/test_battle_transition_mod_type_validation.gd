extends GutTest

## tick 305: BattleTransition._generate_monster_sound now validates
## mod_type before the sample loop and pushes a warning + falls back
## to "growl" on unknown values.
##
## Pre-fix the match statement had 13 arms but NO `_:` default. An
## unknown mod_type (typo in monster profile, new mod_type added to
## data without updating the match, save-format drift) silently left
## `sample = 0.0` for every iteration of the 24000-sample loop —
## producing inaudibly-silent audio. Symptom looked like the SFX
## channel was muted, not "a code path silently fell through".
##
## Validating once before the loop (instead of `_:` inside the
## match) avoids 24000× push_warning calls per generated sound.


const BATTLE_TRANSITION := "res://src/transitions/BattleTransition.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: KNOWN_MOD_TYPES const exists ──────────────────────

func test_known_mod_types_const_exists() -> void:
	var src := _read(BATTLE_TRANSITION)
	assert_true(src.contains("_KNOWN_MOD_TYPES"),
		"_KNOWN_MOD_TYPES const must exist as a validation allowlist")


# ── Const must include every match arm (catches future drift) ────

func test_const_covers_every_match_arm() -> void:
	var src := _read(BATTLE_TRANSITION)
	# Extract match-arm string literals from inside the match block.
	var match_idx: int = src.find("match mod_type:")
	assert_gt(match_idx, -1, "match mod_type: must exist")
	# Find the end of the match block by spotting the line after the
	# last arm. Use the byte-data conversion that comes after.
	var after: int = src.find("# Convert to 8-bit", match_idx)
	assert_gt(after, -1, "must find post-match terminator")
	var match_body: String = src.substr(match_idx, after - match_idx)
	var rx := RegEx.new()
	rx.compile("^\\s+\"([a-z]+)\":")
	var arms: Array[String] = []
	for line in match_body.split("\n"):
		var m := rx.search(line)
		if m != null:
			arms.append(m.get_string(1))
	# Now extract the const allowlist.
	var const_idx: int = src.find("_KNOWN_MOD_TYPES")
	var bracket_open: int = src.find("[", const_idx)
	var bracket_close: int = src.find("]", bracket_open)
	var const_body: String = src.substr(bracket_open, bracket_close - bracket_open + 1)
	var missing: Array[String] = []
	for arm in arms:
		if not const_body.contains("\"" + arm + "\""):
			missing.append(arm)
	assert_eq(missing.size(), 0,
		"_KNOWN_MOD_TYPES must include every match arm (catches drift): %s" % str(missing))


# ── push_warning on unknown mod_type ─────────────────────────────

func test_unknown_mod_type_pushes_warning() -> void:
	var src := _read(BATTLE_TRANSITION)
	assert_true(src.contains("push_warning(\"[BattleTransition] _generate_monster_sound: unknown mod_type"),
		"unknown mod_type must push_warning naming the value")


# ── Fallback to "growl" preserved ────────────────────────────────

func test_unknown_falls_back_to_growl() -> void:
	var src := _read(BattleTransition.resource_path if "resource_path" in BattleTransition else BATTLE_TRANSITION)
	# Just confirm the source: after the warn, mod_type = "growl"
	# happens before the loop.
	assert_true(src.contains("mod_type = \"growl\""),
		"unknown mod_type must fall back to 'growl' (same as the .get() default)")


# ── Validation is OUTSIDE the sample loop (perf) ────────────────

func test_validation_outside_sample_loop() -> void:
	# The validation block must appear BEFORE `for i in range(samples):`
	# so it runs once per generated sound, not 24000× per sound.
	var src := _read(BATTLE_TRANSITION)
	var loop_idx: int = src.find("for i in range(samples):")
	var validate_idx: int = src.find("if not (mod_type in _KNOWN_MOD_TYPES)")
	assert_gt(loop_idx, -1, "sample loop must exist")
	assert_gt(validate_idx, -1, "validation block must exist")
	assert_lt(validate_idx, loop_idx,
		"validation must appear BEFORE the sample loop (else it runs 24000× per sound)")
