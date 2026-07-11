extends GutTest

## struktured playtest 2026-07-11, round 2:
## 1. "victory screen still needs work, too vertical, and gets clipped" —
##    5 simultaneous level-ups made the panel ~700px on a 720px screen.
##    The 3-line level-up block is now ONE compact line and the panel
##    clamps at 680.
## 2. "started a new game, battle speed was 16x, encounter rate 50%,
##    its retaining settings between saves, prob not the right choice" —
##    per-RUN pacing settings reset on New Game; system settings persist.

const BRD_PATH := "res://src/battle/BattleResultsDisplay.gd"
const GL_PATH := "res://src/GameLoop.gd"


func test_level_up_block_is_one_compact_line() -> void:
	var src := FileAccess.get_file_as_string(BRD_PATH)
	assert_false("gain_label" in src,
		"separate stat-gain line must be merged into the compact level-up line")
	assert_false("learn_label" in src,
		"separate learned-abilities line must be merged into the compact level-up line")
	assert_true("char_height_total += 20" in src,
		"height formula must budget ONE line (20px) per level-up")
	assert_false("char_height_total += 22" in src, "old 3-line budget must be gone")


func test_panel_height_is_clamped() -> void:
	var src := FileAccess.get_file_as_string(BRD_PATH)
	assert_true("mini(panel_height, 680)" in src,
		"panel must clamp under the 720px viewport — it clipped off-screen")


func test_new_game_resets_per_run_pacing() -> void:
	var src := FileAccess.get_file_as_string(GL_PATH)
	var fn := src.substr(src.find("func _on_title_new_game"), 1600)
	assert_true("default_battle_speed = 0.25" in fn,
		"New Game must reset battle speed to the 1x default")
	assert_true("encounter_rate_multiplier = 1.0" in fn,
		"New Game must reset encounter rate to 100%")
	assert_true("_battle_speed_index = 0" in fn,
		"New Game must reset the in-battle speed ladder position")
	assert_true("save_settings()" in fn,
		"the reset must persist so the settings file agrees")


func test_save_point_honors_the_input_lock() -> void:
	# "still got the cannot save mid cutscene" — SavePoint._input grabs
	# ui_accept directly and must gate on InputLockManager first.
	var src := FileAccess.get_file_as_string("res://src/exploration/SavePoint.gd")
	var fn := src.substr(src.find("func _input"))
	var lock_idx := fn.find("is_locked()")
	var accept_idx := fn.find("is_action_pressed(\"ui_accept\")")
	assert_gt(lock_idx, -1, "SavePoint._input must consult InputLockManager")
	assert_lt(lock_idx, accept_idx, "the lock gate must come BEFORE the ui_accept branch")


func test_story_cutscene_outranks_llm_dialogue() -> void:
	# "it started with LLM prompt when I chatted with the elder" — the
	# dynamic branch must yield when a story cutscene is pending.
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldNPC.gd")
	assert_true("not story_pending and _llm_conversation_available()" in src,
		"dynamic LLM branch must be gated on no-pending-story-cutscene")
	assert_true("_get_pending_story_cutscene" in src,
		"routing must ask GameLoop for the pending story beat")


func test_command_menu_spawns_for_own_solo_duel() -> void:
	# "can't select any options for my rogue in the spotlight" — the menu
	# gate refused spotlight-locked PCs even in their OWN duel; the
	# watchdog looped 'Menu recovery' forever. Both gates (routing AND
	# menu) must carry the solo-duel override.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_true("own_solo_duel" in src,
		"menu gate must compute the own-solo-duel override")
	assert_true("not debug_override and not own_solo_duel" in src,
		"the silent-return must be skipped for a locked PC in their own duel")
	assert_true("player_party.size() == 1" in src.substr(src.find("own_solo_duel")),
		"override must match the routing gate's solo-party conjunct")


func test_danger_music_switchback_is_stateless() -> void:
	# "playing the ur about to die music" over a restored party — the
	# duel retry rebuilds BattleScene with _is_danger_music=false while
	# SoundManager still plays danger; the flag-only check never switched
	# back. The recovered branch must also consult the LIVE track.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true("_current_music) == \"danger\"" in src,
		"switch-back must consult SoundManager's live track, not only the per-scene flag")
