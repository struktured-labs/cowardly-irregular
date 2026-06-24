extends GutTest

## tick 99 regression: bard spotlight cutscene must trigger via
## _get_pending_story_cutscene so Bard unlocks manual control.
## Completes the spotlight series started in ticks 97 (cleric) and
## 98 (rogue + mage). Bard was the final non-Fighter PC still stuck
## in permanent autobattle-lock.
##
## Original design point was "capital gate" (Scriptura) per the
## _CUTSCENE_COMPLETION_FLAGS comment, but village_capital is
## registered in locations.json without an actual scene route —
## the capital isn't reachable in W1. Bard instead unlocks on
## return to harmonia_village after rat king defeat (chapter4_complete).

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _pending_cutscene_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1, "_get_pending_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_bard_spotlight_returnable() -> void:
	var body := _pending_cutscene_body()
	assert_true(body.contains("return \"world1_spotlight_bard_ch7\""),
		"_get_pending_story_cutscene must return world1_spotlight_bard_ch7 — otherwise bard stays autobattle-locked permanently")


func test_bard_gate_uses_chapter4_complete_predicate() -> void:
	var body := _pending_cutscene_body()
	assert_true(body.contains("flags.get(\"cutscene_flag_chapter4_complete\", false) and not flags.get(\"cutscene_flag_spotlight_unlocked_bard\", false)"),
		"bard spotlight gate must check chapter4_complete + not unlocked_bard — fires after rat king defeat on return to village")


func test_bard_gate_scoped_to_harmonia_village() -> void:
	var body := _pending_cutscene_body()
	var idx: int = body.find("return \"world1_spotlight_bard_ch7\"")
	assert_gt(idx, -1, "bard spotlight return must exist")
	var window_start: int = max(0, idx - 200)
	var window: String = body.substr(window_start, idx - window_start)
	assert_true(window.contains("_current_map_id == \"harmonia_village\""),
		"bard spotlight must be gated on harmonia_village — Scriptura not reachable in W1, harmonia is the natural fallback")


func test_bard_gate_precedes_chapter9_auto_set() -> void:
	# Ordering: bard gate must come BEFORE the chapter9 auto-set
	# block (which auto-sets chapter7_complete and others). If the
	# bard gate were placed after, the natural trigger window (when
	# chapter4 is set but chapter9 isn't yet) would never apply
	# because chapter9 auto-sets immediately.
	#
	# Actually the bard gate uses chapter4 directly, NOT chapter9,
	# so ordering with the auto-set block doesn't strictly matter
	# for the bard gate itself. But the test still pins the
	# ordering as a stability anchor for future tweaks.
	var body := _pending_cutscene_body()
	var bard_idx: int = body.find("return \"world1_spotlight_bard_ch7\"")
	var auto_set_idx: int = body.find("for skip_flag in [\"chapter5_complete\"")
	assert_gt(bard_idx, -1, "bard gate must exist")
	assert_gt(auto_set_idx, -1, "chapter5-9 auto-set loop must exist")
	assert_lt(bard_idx, auto_set_idx,
		"bard spotlight gate must precede the chapter5-9 auto-set loop in source — keeps the spotlight at the natural narrative beat")


func test_bard_cutscene_file_exists_and_sets_correct_flag() -> void:
	var path := "res://data/cutscenes/world1_spotlight_bard_ch7.json"
	assert_true(FileAccess.file_exists(path), "%s must exist on disk" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	assert_true(text.contains("\"spotlight_unlocked_bard\""),
		"bard spotlight cutscene must set the spotlight_unlocked_bard flag")


func test_all_four_non_fighter_spotlights_now_reachable() -> void:
	# Final coverage assertion: every non-Fighter PC (Cleric, Rogue,
	# Mage, Bard) has at least one return path in
	# _get_pending_story_cutscene. Confirms the full spotlight
	# series (ticks 97 + 98 + 99) closed the spotlight gap.
	var body := _pending_cutscene_body()
	for cutscene_id in ["world1_spotlight_cleric_ch1", "world1_spotlight_rogue_ch3", "world1_spotlight_mage_ch3", "world1_spotlight_bard_ch7"]:
		assert_true(body.contains("return \"" + cutscene_id + "\""),
			"%s must have a return path — completing the spotlight series ensures every non-Fighter PC can unlock manual control through normal play" % cutscene_id)


func test_fighter_spotlight_intentionally_skipped() -> void:
	# Hero/Fighter is the lead PC — autobattle_locked = false at
	# _create_party, no spotlight needed. The world1_spotlight_fighter_ch2
	# cutscene exists but is intentionally NEVER triggered by
	# _get_pending_story_cutscene because Fighter isn't gated.
	var body := _pending_cutscene_body()
	assert_false(body.contains("return \"world1_spotlight_fighter_ch2\""),
		"Fighter spotlight must NOT be in _get_pending_story_cutscene — Fighter is unlocked at party creation (hero.autobattle_locked = false)")
