extends GutTest

## msg 2570 #2 / msg 2581: the same double-scale bug cowir-main killed at
## the confused-attack site (BM:3051 in v3.33.137) was still live at the
## MAIN inter-action delay (BM ~3126) and the group-action post-execute
## delay (BM ~3255). Both computed `delay = 0.1 / Engine.time_scale`
## then handed the result to `create_timer(delay)` — which itself already
## respects Engine.time_scale by default (ignore_time_scale=false). Net
## effect at 1x (time_scale=0.25): timer=0.4, wall=0.4/0.25=1.6s per
## action instead of the authored 0.1s.
##
## 2026-07-17 cinematic pacing: timers now route through _consume_presentation_hold(base) which returns the SAME constant when no hold is requested — the anti-double-scale intent pinned here is unchanged.
## Fix: constant `create_timer(0.025).timeout` mirroring the 3051 fix.
## At 1x that lands at 0.025/0.25 = 0.1s wall — the intent stated in the
## BM:3117 comment.
##
## Per-action wall-clock savings at 1x: **1.5 seconds**. At a 5-party
## table that's ~7.5s of dead air removed per round — the "transaction
## feel" struktured called out (msg 2570).
##
## Watchdog interaction: _wd_bump() fires at the top of
## _execute_next_action (BM:2967). More frequent _execute_next_action
## calls = more frequent bumps = safer, not tighter, against the
## _WD_STALL_MS threshold. Trust-interrupt window (BM:1431) is a
## separate create_timer call untouched by this fix. Round-banner
## suppression (v3.33.176 BattleScene-side) is downstream and
## unaffected.

const BM_PATH: String = "res://src/battle/BattleManager.gd"


## ── The constant timer is in place at both sites ──────────────────────

func test_main_inter_action_delay_uses_constant_025() -> void:
	# Anchor on the distinctive comment I added so this test can't be
	# fooled by matching the confused-attack site (which uses the same
	# constant but a different neighborhood).
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("msg 2570/2581: was 0.1/speed_scale which DOUBLE-scaled")
	assert_gt(idx, -1, "the msg 2570/2581 fix comment must be present at the main inter-action delay site")
	var body: String = src.substr(idx, 400)
	assert_string_contains(body, "await get_tree().create_timer(_consume_presentation_hold(0.025)).timeout",
		"main inter-action delay must use constant 0.025 (0.1s wall at 1x)")


func test_group_action_delay_uses_constant_025() -> void:
	# Same fix, second site — anchor on the group-action-specific comment.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("same double-scale fix as _execute_next_action's inter-action delay")
	assert_gt(idx, -1, "the group-action fix comment must be present at the _execute_group_action delay site")
	var body: String = src.substr(idx, 400)
	assert_string_contains(body, "await get_tree().create_timer(_consume_presentation_hold(0.025)).timeout",
		"group-action delay must use constant 0.025 (0.1s wall at 1x)")


## ── The double-scale pattern must not re-appear at either site ────────

func test_no_double_scaled_delay_in_execute_next_action_body() -> void:
	# Textual guard: the `delay = 0.1 / speed_scale` pattern is the exact
	# bug shape. If a future refactor reintroduces it (e.g., because
	# someone wants to make the delay "responsive to speed"), this test
	# fires and points them at the msg 2570/2581 investigation.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _execute_next_action() -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 6000)
	assert_false(body.find("var delay = 0.1 / speed_scale") > -1,
		"the double-scaled `delay = 0.1 / speed_scale` bug must not reappear in _execute_next_action — create_timer already respects Engine.time_scale, so this pattern silently 4x-inflates the delay at 1x")


func test_no_double_scaled_delay_in_execute_group_action_body() -> void:
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _execute_group_action(action: Dictionary) -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 6000)
	assert_false(body.find("var delay = 0.1 / speed_scale") > -1,
		"the double-scaled `delay = 0.1 / speed_scale` bug must not reappear in _execute_group_action")


## ── The already-known 3051 confused-attack constant stays put ─────────

func test_confused_attack_delay_still_025() -> void:
	# The v3.33.137 fix should stay in place. If someone accidentally
	# reverts the confused-attack constant they'll silently reintroduce
	# a 1.5s delay every confusion turn.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("Constant 0.025 gives the intended 0.1s at 1x")
	assert_gt(idx, -1, "the v3.33.137 confused-attack fix comment must remain as history + guard")
	var body: String = src.substr(idx, 300)
	assert_string_contains(body, "await get_tree().create_timer(_consume_presentation_hold(0.025)).timeout",
		"confused-attack delay must still be constant 0.025 (v3.33.137 fix intact)")


## ── The turbo-mode path is unchanged ──────────────────────────────────

func test_turbo_mode_still_uses_process_frame() -> void:
	# Turbo mode skips the timer entirely and awaits a single frame —
	# preserving that shape is the whole point of turbo. If someone
	# accidentally replaces `process_frame` with a timer they reintroduce
	# a floor delay under turbo.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _execute_next_action() -> void:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 6000)
	assert_string_contains(body, "if turbo_mode:\n\t\tawait get_tree().process_frame",
		"turbo path must remain process_frame-only — no floor delay under turbo")
