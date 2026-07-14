extends GutTest

## tick 280: wanderer hint flag wiring.
##
## Two-prong fix:
##   1. WanderingNPC._get_current_dialogue now checks BOTH namespaces
##      (story_flags AND cutscene_flag_X / bare X in game_constants).
##      Pre-fix only story_flags was checked, so W1 hints referencing
##      bare cutscene names (prologue_complete, chapter1_complete,
##      chapter3_complete) never matched — every reference lived in
##      game_constants as cutscene_flag_X.
##
##   2. W2-W5 hint boss flags renamed from dead `w<N>_boss_defeated`
##      to the real cutscene_flag_<boss>_defeated form. tick 278
##      proved these flags have no writers.
##
##      `w<N>_entered` is KEPT — each overworld's _setup_scene calls
##      set_story_flag("w<N>_entered") (verified at grep time).

const WANDERING_NPC := "res://src/exploration/WanderingNPC.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── _get_current_dialogue uses _flag_set helper ────────────────────

func test_flag_set_helper_exists() -> void:
	var src := _read(WANDERING_NPC)
	assert_true(src.contains("func _flag_set(flag: String) -> bool"),
		"_flag_set helper must exist (centralizes dual-namespace check)")


func test_flag_set_checks_all_three_namespaces() -> void:
	var src := _read(WANDERING_NPC)
	assert_true(src.contains("GameState.get_story_flag(flag)"),
		"_flag_set must check story_flags namespace")
	assert_true(src.contains("GameState.game_constants.get(\"cutscene_flag_\" + flag, false)"),
		"_flag_set must check game_constants with cutscene_flag_ prefix")
	assert_true(src.contains("GameState.game_constants.get(flag, false)"),
		"_flag_set must check bare flag in game_constants too")


# ── W2-W5 hint boss flags use the real form ────────────────────────

const WORLD_FILES := {
	"res://src/exploration/SuburbanOverworld.gd": {
		"dead": "w2_boss_defeated",
		"real": "warden_suburban_defeated",
	},
	"res://src/exploration/SteampunkOverworld.gd": {
		"dead": "w3_boss_defeated",
		"real": "tempo_steampunk_defeated",
	},
	"res://src/exploration/IndustrialOverworld.gd": {
		"dead": "w4_boss_defeated",
		"real": "warden_industrial_defeated",
	},
	"res://src/exploration/FuturisticOverworld.gd": {
		"dead": "w5_boss_defeated",
		"real": "arbiter_futuristic_defeated",
	},
}


func test_dead_boss_flags_no_longer_in_hints() -> void:
	var survivors: Array[String] = []
	for path in WORLD_FILES:
		var src := _read(path)
		var dead: String = WORLD_FILES[path]["dead"]
		# Check the hint-arm specifically — `"flag": "<dead>"`.
		if src.contains("\"flag\": \"" + dead + "\""):
			survivors.append("%s still has hint with flag=%s" % [path, dead])
	assert_eq(survivors.size(), 0,
		"each W2-W5 overworld must NOT reference its dead w<N>_boss_defeated flag in hints: %s" % str(survivors))


func test_real_boss_flags_now_in_hints() -> void:
	var missing: Array[String] = []
	for path in WORLD_FILES:
		var src := _read(path)
		var real: String = WORLD_FILES[path]["real"]
		if not src.contains("\"flag\": \"" + real + "\""):
			missing.append("%s missing hint with flag=%s" % [path, real])
	assert_eq(missing.size(), 0,
		"each W2-W5 overworld must reference its real boss flag in hints: %s" % str(missing))


# ── W*_entered flags STAY (they are written by the overworld) ─────

func test_w_entered_flags_preserved() -> void:
	# Spot-check: each W2-W5 overworld must still set_story_flag("w<N>
	# _entered") AND still reference "w<N>_entered" in hints.
	for path in WORLD_FILES:
		var src := _read(path)
		var dead: String = WORLD_FILES[path]["dead"]
		# Derive expected w<N>_entered from the dead boss flag name.
		var w_entered: String = dead.replace("_boss_defeated", "_entered")
		assert_true(src.contains("set_story_flag(\"" + w_entered + "\")"),
			"%s must still call set_story_flag(\"%s\") in _setup_scene" % [path, w_entered])
		assert_true(src.contains("\"flag\": \"" + w_entered + "\""),
			"%s must still reference \"%s\" in dialogue hints" % [path, w_entered])


# ── Behavioral: hint flips when the real flag is set ─────────────

func test_hint_resolves_via_cutscene_flag_prefix() -> void:
	# Use a small fixture: instantiate WanderingNPC with a hint that
	# references a bare name, set the corresponding cutscene_flag_ in
	# game_constants, assert _flag_set returns true.
	var script: GDScript = load(WANDERING_NPC)
	var npc: Object = script.new()
	add_child_autofree(npc)
	npc.dialogue = "default"
	npc.dialogue_hints = [
		{"flag": "test_flag_for_280", "text": "advanced"},
	]
	# Pre: no flag set anywhere.
	GameState.story_flags.erase("test_flag_for_280")
	GameState.game_constants.erase("cutscene_flag_test_flag_for_280")
	GameState.game_constants.erase("test_flag_for_280")
	assert_eq(npc._get_current_dialogue(), "default",
		"baseline: no flag → default dialogue")
	# Set the cutscene_flag_ form in game_constants.
	GameState.game_constants["cutscene_flag_test_flag_for_280"] = true
	assert_eq(npc._get_current_dialogue(), "advanced",
		"cutscene_flag_ form in game_constants must satisfy the hint check (was dead pre-tick-280)")
	# Cleanup.
	GameState.game_constants.erase("cutscene_flag_test_flag_for_280")
