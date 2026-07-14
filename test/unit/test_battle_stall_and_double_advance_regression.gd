extends GutTest

## Playtest 2026-07-12 (v3.33.136), two battle bugs:
##
## BUG 1 — 15-20s stall between turns. A spotlight-locked PC (or a debug-
## all-PCs-unlocked PC) left unattended in PLAYER_SELECTING sits with no
## visible menu; the menu-watchdog burns 4x2500ms (grace + 3 retries) before
## the terminal autobattle fallback. Fix: a locked PC skips the retry ladder
## and autobattle-resolves after ONE grace period — EXCEPT its own solo duel
## (must not steal the duelist's turn).
##
## BUG 4 — one trigger squeeze queued TWO Advances. battle_advance bound BOTH
## the RB button AND the right-trigger axis; one physical pull emits both
## events, each satisfies is_action_pressed, no debounce. Fix: drop the
## drifting analog-trigger axis bindings (keep RB/LB + keys) + a 120ms
## advance debounce.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")


func test_menu_watchdog_fast_paths_locked_pc_but_not_solo_duel() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _tick_menu_watchdog")
	assert_gt(i, -1, "_tick_menu_watchdog must exist")
	var body := src.substr(i, 1600)
	assert_true("autobattle_locked" in body and "execute_autobattle_for_current" in body,
		"a locked PC must autobattle-resolve instead of burning the ~10s force-spawn ladder")
	assert_true("own_solo_duel" in body,
		"the fast-path must exclude a PC's own solo duel so it never steals the duelist's manual turn")


func test_menu_wd_diag_reports_debug_unlock_flag() -> void:
	# The stall was hard to diagnose because the diag didn't surface
	# debug_all_pcs_unlocked (the actual gate that left the PC manual).
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true("dbg_unlocked" in src,
		"_menu_wd_diag must report debug_all_pcs_unlocked so the next cap is unambiguous")


func test_advance_double_fire_guarded_by_debounce() -> void:
	# 2026-07-12: dropping the trigger-axis binding BROKE Advance for trigger
	# users (they advance with the RT axis, not the RB button). So we KEEP all
	# bindings (RB/LB buttons + RT/LT axes + keys) and guard the drifting-
	# trigger double-fire with a wall-clock debounce instead.
	var w := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true("const ADVANCE_DEBOUNCE_MS" in w, "advance debounce const must exist")
	var i := w.find("func _handle_advance_input")
	assert_gt(i, -1)
	var body := w.substr(i, 600)
	assert_true("_last_advance_ms" in body and "ADVANCE_DEBOUNCE_MS" in body,
		"_handle_advance_input must debounce rapid duplicate advances (cross-source button+axis / trigger jitter)")
	# All Advance bindings remain so RB, RT, and keyboard all work.
	var pg := FileAccess.get_file_as_string("res://project.godot")
	var adv := pg.substr(pg.find("battle_advance="), pg.find("battle_defer=") - pg.find("battle_advance="))
	assert_true("button_index\":10" in adv, "battle_advance keeps RB (button 10)")


func test_render_smoke_neutralizes_debug_unlock() -> void:
	# A dev box's settings.json can carry debug_all_pcs_unlocked=true, which
	# force-clears is_player_trusted (BattleManager) and stalls the smoke's
	# game-over auto-play leg. The smoke must reset it for determinism.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _maybe_run_battle_smoke")
	assert_gt(i, -1, "smoke entry must exist")
	var body := src.substr(i, 900)
	assert_true("debug_all_pcs_unlocked = false" in body,
		"render smoke must force debug_all_pcs_unlocked=false so dev settings can't break the game-over leg")


func test_advance_debounce_suppresses_rapid_double_fire() -> void:
	var menu = Win98MenuClass.new()
	add_child_autofree(menu)
	menu.is_root_menu = true
	menu.battle_mode = true
	menu.setup("T", [{"id": "attack", "label": "Attack", "data": {}}], Vector2.ZERO, "fighter")
	menu.set_max_queue_size(4)
	menu.set_current_ap(4)
	menu._can_accept_input = true
	menu._last_advance_ms = 0

	menu._handle_advance_input()
	var after_first: int = menu._queued_actions.size()
	assert_eq(after_first, 1, "first Advance queues one action")
	# Immediate second call (same ms, within ADVANCE_DEBOUNCE_MS) must be ignored.
	menu._handle_advance_input()
	assert_eq(menu._queued_actions.size(), after_first,
		"a second Advance within the debounce window must NOT queue a second action (one squeeze = one action)")
	# Simulate the debounce window elapsing — a genuine later press must work.
	menu._last_advance_ms = 0
	menu._handle_advance_input()
	assert_eq(menu._queued_actions.size(), after_first + 1,
		"an Advance after the debounce window must queue normally")
