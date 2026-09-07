extends GutTest

## Queue #4 option (a) (cowir-main msg 2154): B-cancel during a trusted PC's
## auto-turn interrupts + hands the turn back to manual control. Complements
## the Settings-side untrust (test_settings_menu_party_trust_regression) with
## an in-battle felt-experience path.
##
## Guards the SURFACE (BM signals, window state, request handler) — the
## BattleScene input-capture path is a source-pin (input plumbing needs a
## live tree).

const BM_PATH: String = "res://src/battle/BattleManager.gd"


func _bm() -> Node:
	var bm: Node = load(BM_PATH).new()
	add_child_autofree(bm)
	return bm


func _pc(job_id: String = "fighter") -> Combatant:
	var c := Combatant.new()
	c.combatant_name = job_id
	c.job = JobSystem.get_job(job_id)
	c.job_level = 1
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


## ── Signals and state contract ──────────────────────────────────────────

func test_bm_declares_the_two_trust_window_signals() -> void:
	var bm := _bm()
	assert_true(bm.has_signal("trust_interrupt_window_opened"),
		"opened signal drives BattleScene's toast + input arming")
	assert_true(bm.has_signal("trust_interrupt_window_closed"),
		"closed signal lets BattleScene tear down whatever it armed")


func test_window_state_is_closed_by_default() -> void:
	var bm := _bm()
	assert_false(bm.is_trust_interrupt_window_open(),
		"no window is armed on a fresh BM")
	assert_eq(bm.request_trust_interrupt(), false,
		"a request with no window returns false so BattleScene can pass the input through")


## ── Request handler clears player_trust and disarms the window ──────────

func test_request_clears_player_trust_and_closes_window() -> void:
	var bm := _bm()
	var pc := _pc()
	pc.player_trust = true
	bm._trust_window_pc = pc
	assert_true(bm.is_trust_interrupt_window_open(),
		"seeding the window field opens the window (implementation detail — the request path this test drives depends on it)")
	assert_true(bm.request_trust_interrupt(), "live window → request returns true")
	assert_false(pc.player_trust, "one-shot untrust cleared player_trust")
	assert_false(bm.is_trust_interrupt_window_open(), "window is now closed")
	assert_eq(bm.request_trust_interrupt(), false,
		"a second request in the same window is a no-op")
	pc.free()


## ── request_trust_interrupt is a no-op on spotlight-locked PCs ──────────

func test_request_is_a_noop_when_no_pc_is_armed() -> void:
	# Even if a spotlight-locked PC is mid-selection, the trust window
	# NEVER opens for them (BM._process_next_selection routing guards
	# on is_player_trusted and not is_spotlight_locked). Textual pin
	# on the source keeps that guard from silently degrading.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "not is_spotlight_locked",
		"trust window must skip when spotlight-locked (story-gated turn)")
	assert_string_contains(src, "not is_autobattle_enabled",
		"trust window must skip when global autoscript is on (player already opted out)")
	assert_string_contains(src, "not is_char_autobattle",
		"trust window must skip when this specific PC has autobattle enabled globally")


## ── BattleScene input capture and routing paths are wired ───────────────

func test_battle_scene_captures_ui_cancel_during_open_window() -> void:
	const SCENE_PATH := "res://src/battle/BattleScene.gd"
	var src: String = FileAccess.get_file_as_string(SCENE_PATH)
	assert_string_contains(src, "BattleManager.is_trust_interrupt_window_open()",
		"BattleScene must consult BM before swallowing cancel (else it'll interrupt other UI paths)")
	assert_string_contains(src, "BattleManager.request_trust_interrupt()",
		"BattleScene must actually request the interrupt on ui_cancel")


func test_battle_scene_connects_the_window_signals() -> void:
	const SCENE_PATH := "res://src/battle/BattleScene.gd"
	var src: String = FileAccess.get_file_as_string(SCENE_PATH)
	assert_string_contains(src, "trust_interrupt_window_opened.connect",
		"connect the opened signal so future toast/highlight polish has an anchor")
	assert_string_contains(src, "trust_interrupt_window_closed.connect",
		"connect the closed signal for the symmetric tear-down")


## ── Guard against stale AI action if player picked mid-window ───────────

func test_run_window_no_ops_ai_when_current_combatant_changed() -> void:
	# Source-pin on the guard that stops _process_ai_selection from being
	# called on a PC whose selection has already advanced (player picked
	# a menu action during the trust window).
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "if current_combatant != pc:",
		"guard against stale AI action after player picked mid-window")
