extends GutTest

## tick 96 regression: W3 chapter4 (the post-defeat Regulator
## dialogue closing the steampunk arc) must gate on the W3
## Mechanism's boss-defeat flag, NOT on the W4 Industrial warden's
## flag.
##
## Pre-fix, GameLoop._get_pending_story_cutscene at line ~1067
## checked `cutscene_flag_warden_industrial_defeated` — a flag set
## by AssemblyCore (W4). Meanwhile SteampunkMechanism (W3) set NO
## defeat flag at all. So the W3 narrative closer only triggered
## after the player beat the W4 boss — completely skipping the W3
## arc payoff. The Regulator's "you exceeded the adjustment again"
## dialogue would surface mid-W4 instead of closing W3.
##
## Fix: SteampunkMechanism now sets a new W3-specific flag
## (`cutscene_flag_tempo_steampunk_defeated`), and the chapter4
## gate consumes it.

const GAME_LOOP := "res://src/GameLoop.gd"
const STEAMPUNK_MECHANISM := "res://src/maps/dungeons/SteampunkMechanism.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_steampunk_mechanism_sets_tempo_steampunk_defeated_flag() -> void:
	var src := _read(STEAMPUNK_MECHANISM)
	assert_true(src.contains("defeat_cutscene_flags = [\"cutscene_flag_tempo_steampunk_defeated\"]"),
		"SteampunkMechanism must set defeat_cutscene_flags with the W3-specific flag — without it, W3 chapter4 never triggers from a W3 boss defeat")


func test_w3_chapter4_gate_uses_steampunk_flag() -> void:
	var src := _read(GAME_LOOP)
	# Pin the new gate.
	assert_true(src.contains("flags.get(\"cutscene_flag_tempo_steampunk_defeated\", false):\n\t\t\treturn \"world3_chapter4\""),
		"W3 chapter4 gate must check cutscene_flag_tempo_steampunk_defeated — the W3 Mechanism boss's own flag")


func test_w3_chapter4_gate_no_longer_uses_warden_industrial_flag() -> void:
	# Negative pin: the gate that returns "world3_chapter4" must NOT
	# reference the W4 flag. A future revert would silently re-break
	# the W3 narrative arc.
	var src := _read(GAME_LOOP)
	# Find the chapter4 return site and look at the line above for
	# the flag check.
	var idx: int = src.find("return \"world3_chapter4\"")
	assert_gt(idx, -1, "W3 chapter4 return site must exist")
	# Look back ~200 chars for the gating flag.
	var window_start: int = max(0, idx - 200)
	var window: String = src.substr(window_start, idx - window_start)
	assert_false(window.contains("cutscene_flag_warden_industrial_defeated"),
		"W3 chapter4 gate must NOT reference the W4 flag — that was the original bug")


func test_w4_assembly_core_still_owns_warden_industrial_flag() -> void:
	# Sanity: don't accidentally rename the W4 boss flag. AssemblyCore
	# still emits warden_industrial_defeated for whatever consumers
	# downstream might use it (currently none in GameLoop, but the
	# bridge stays for completeness).
	var src := _read("res://src/maps/dungeons/AssemblyCore.gd")
	assert_true(src.contains("\"cutscene_flag_warden_industrial_defeated\""),
		"AssemblyCore must still declare cutscene_flag_warden_industrial_defeated in defeat_cutscene_flags — unrelated to W3, but documents W4 boss provenance")


func test_w3_dragon_cave_chain_unchanged() -> void:
	# Don't regress the other W3 chapter gates by accidentally touching
	# the surrounding code.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("return \"world3_prologue\""),
		"W3 prologue gate intact")
	assert_true(src.contains("return \"world3_chapter1\""),
		"W3 chapter1 gate intact")
	assert_true(src.contains("return \"world3_chapter2\""),
		"W3 chapter2 gate intact")
	assert_true(src.contains("return \"world3_chapter3\""),
		"W3 chapter3 gate intact")
	assert_true(src.contains("return \"world3_chapter5\""),
		"W3 chapter5 gate intact")
